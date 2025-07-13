#!/bin/bash 
#

shopt -s extglob		# needed for sortkeyincr()


CJRLIB="/usr/local/lib/cjrlib/bash"
. "$CJRLIB/vlog.shinc"
. "$CJRLIB/sys.shinc"
. "$CJRLIB/net.shinc"
. "$CJRLIB/data.shinc"
. "$CJRLIB/aarray.shinc"
. "$CJRLIB/file.shinc"
. "$CJRLIB/string.shinc"

DRIVE_INFO_DIR="/House/INSTALL/Common/DRIVE_INFO"
DRIVE_INFO_PATH="$DRIVE_INFO_DIR/$(basename "$0")"		# this file

PROGPATH="$(file_absolute_path "$0")"

# external commands
LSBLK=lsblk
WMIC=wmic
SSH=ssh

# just to stand out better
VEXEC=vexec
VVEXEC=vvexec
VVVEXEC=vvvexec

#===============================================================================
# REPORT definitions
# NB: SORTKEYS must use the form -k KEYDEF (rather than --key=KEYDEF)
# NOTES:
#	- use Drive instead of Serial in case of missing INFO.txt
#	- Comment the field in its primary report

#=======================================
REPORT_STATUS_DESC="Default report by Status, Location."
REPORT_STATUS_SORTKEYS="-k 5,6 -k 6"
REPORT_STATUS=(
		DI:Name:18
		DI:Size:6
		DI:Drive:18			# drive subdirectory == Serial
		DI:Type:6
		DI:Status:6
		DI:Location:12		
)

#=======================================
REPORT_INFO_DESC="Info report by Status, HostOS, Hostname"
REPORT_INFO_SORTKEYS="-k 5,6 -k 6,7 -k 7"
REPORT_INFO=(
		DI:Name:18			# My name for the drive <hostname>-<name>, etc
		DI:Size:6			# friendly size
		DI:Serial:18		# Serial number printed on the drive
		DI:Type:6			# HDD | SSD | NVMe
		DI:Status:6			# ACTIVE | STOWED
		DI:HostOS:4			# LNX | WIN | MAC
		DI:Hostname:8		# short hostname
		# DI:Model:20		# Model that smartctl reports
		DI:ProductName:28	# friendlier Model (copied from Model if empty)
		DI:Firmware:10		# Firmware that smartctl reports
		DI:SysID:40			# Serial that OS reports; see ACTIVE (below)
		DI:SmartctlOpts:16	# options to smartctl -x, usually a -d <device>
		DI:Bytes:18			# size in bytes with commas
		DI:NOTES:12			# my notes, at end of file, can be multi-line
)
REPORT_INFO_MASSAGER() {
	dlog "${FUNCNAME[0]}($*)"
	local drive="$1"; shift

	# Suppress sysid if it's the same as serial/drive
	if [ "$(DIget SysID)" == "$drive" ]; then
		DIset SysID ''
	fi
}


#=======================================
REPORT_ACTIVE_DESC="Active drive report by Location."
REPORT_ACTIVE_SORTKEYS="-k 7"
REPORT_ACTIVE=(
		DI:Name:18
		DI:Size:6
		DI:Drive:18			# == Serial
		DI:Type:6
		DI:Dev:8			# active device; (volatile; can change on reboot)
		DI:Tran:5			# Transport (sata, usb, etc) reported by OS
		DI:Location:12		# hostname.{INT|NVMe|EXT}[.enclosure-code]
)

#=======================================
REPORT_STOWED_DESC="Stowed drive report by Location, StowDate."
REPORT_STOWED_SORTKEYS="-k 7,8 -k 5,6"
REPORT_STOWED=(
		DI:Name:18
		DI:Size:6
		DI:Drive:18			# == Serial
		DI:ProductName:24
		DI:StowDate:10		# yyyy/mm/dd	Date removed from active
		DI:StowChecked:10	# yyyy/mm/dd	Date last checked location
		DI:Location:22		# my location codes  XXX: see LOCATIONS.txt
		DI:NOTES:1
)

REPORT_STOWED_MASSAGER(){
	dlog "${FUNCNAME[0]}($*)"
	local drive="$1"; shift
	local pname

	# make sure ProductName contains no spaces (so the above sort works)
	pname="$(DIget ProductName)"
	pname="${pname// /_}"
	DIset ProductName "$pname"
}

#=======================================
REPORT_SMART_DESC="All raw SMART data for drive by Name."
REPORT_SMART_SORTKEYS="-k 1"
REPORT_SMART=(
		DI:Name:18
		DI:Size:6
		DI:Drive:18			# == Serial
		DS:Date:10			# smartctl -x date
		DS:SMART:4			# SMART self-assessment status:  OK | <not>

		# NVMe Log 0x02
		DS:LifeUsed:6		# Percentage Used; 
		DS:DataErrors:4		# Media and Data Integrity Errors
		DS:ErrLogs:4		# Error Information Log Entries
		DS:WarnTempT:4		# Time spent in warning temp (seconds?)
		DS:CritTempT:4		# Time spent in critical temp (seconds?)
		DS:CritWarn:6		# Critical Warning (hex code)

		# Vendor-specific SMART attributes
		DS:ReadErrRate:4	#   1 Raw_Read_Error_Rate
		DS:ReallocBlks:6	#   5 Reallocated_Sector_Ct / Reallocated_NAND_Blk
		DS:PwrOnHours:8		#   9 Power_On_Hours
		DS:PwrCycles:8		#  12 Power_Cycle_Count
		DS:HeliumPct:3		#  22 (Western Digital) Helium charge percent
		DS:WearLvlCnt:6		# 177 Wear Leveling Count
		DS:RTBadBlock:6		# 183 Runtime_Bad_Block
		DS:ECCErrs:6		# 184 Error_Correction_Count | End-to-End_Error
		DS:LoadCycles:8		# 193 Load_Cycle_Count
		DS:Temp:3			# 194 Temperature_Celcius
		DS:PendSector:6		# 197 Current_Pending_Sector
		DS:OfflUncorr:6		# 198 Offline_Uncorrectable
		DS:UDMAErrors:6		# 199 UDMA_CRC_Error_Count
		DS:WrErrRt:6		# 206 Write_Error_Rate
		DS:WearoutInd:4		# 233 Media_Wearout_Indicator
		DS:PwrOffRcvy:6		# 235 POR (PowerOff) Recovery Count

		# Device Statistics (GP Log 0x04)
		DS:OverTempT:4		# 0x05 0x050  Time in Over-Temperature (seconds?)
		DS:Dev040:6			# 0xff 0x040	- WD 12TB HDD; keeps changing
		DS:Dev048:6			# 0xff 0x048	- WD 12TB HDD; keeps changing
		DS:Dev080:6			# 0xff 0x080	- WD 12TB HDD; keeps changing
		
		# SCT Status
#		DS:Temp:3			# Current Temperature (celcius) [filled above]
		DS:PCTempMM:6		# Power Cycle Min/Max Temperature (celcius)
		DS:LTempMM:6		# Lifetime Min/Max Temperature (celcius)
)

#======================================
function set_STATS_meta()
# Create DS meta (m_) entries for current drive.
{
	dlog "${FUNCNAME[0]}($*)"
	local val

	# m_TOTErrs				# total error count
	#	ErrLogs can have spurious unsupported "Invalid Log Page" errors
	# 	EXCLUDE THESE:
#			+ $(getDSval UDMAErrors)		# cabling issues
	DSset m_TOTErrs $((
			  $(getDSval DataErrors)
			+ $(getDSval ErrLogs)
			+ $(getDSval ReadErrRate)
			+ $(getDSval PendSector)
			+ $(getDSval OfflUncorr)
			+ $(getDSval WrErrRt)
			+ $(getDSval RTBadBlock)
			+ $(getDSval ECCErrs)
			+ $(getDSval WearoutInd)
		))

	# m_TOTRealloc			# total reallocated blocks/events
	DSset m_TOTRealloc $((
			  $(getDSval ReallocCnt)
			+ $(getDSval ReallocBlks)
		))
	
	# m_LifeLeft			# percent of life left
	val="$(DSget HeliumPct)"
	val="${val%%%}"			# trim any %
	val2="$(DSget LifeUsed)"
	val2="${val2%%%}"		# trim any %
	if [ -n "$val" ]; then
		DSset m_LifeLeft "${val}%"
		if [ -n "$val2" ]; then
			logwarn "Both HeliumPct(HDD) and LifeUsed(SSD) are defined!"
		fi
	elif [ -n "$val2" ]; then
		DSset m_LifeLeft $(( 100 - val2 ))%
	fi

	# m_TempWarn 			# total overtemp time score
	DSset m_TempWarn $((
			  $(getDSval OverTempT )
			+ $(getDSval WarnTempT )
			+ 100 * $(getDSval CritTempT )
		))

	# parse Temp MinMax
	val="$(DSget LTempMM)"
	if [ -n "$val" ]; then
		val="${val##*/}"
		DSset m_MaxLTemp "${val}C"	# maximum lifetime temperature
	fi
}


#=======================================
REPORT_HEALTH_DESC="Simple drive health report by Date."
REPORT_HEALTH_SORTKEYS="-k 5,6"
REPORT_HEALTH=(
		DI:Name:18
		DI:Size:6
		DI:Type:6
		DI:Drive:18			# == Serial
		DS:Date:10
		DS:SMART:4			# smart status
		DS:m_TOTErrs:4		# total error count (of all types)
		DS:m_TOTRealloc:4	# total reallocated blocks/events
		DS:m_TempWarn:4		# total overtemp time score
		DS:m_MaxLTemp:4	 	# maximum lifetime temperature
		DS:m_LifeLeft:4		# life remaining
)

#=======================================
REPORT_META1_DESC="Drive meta m_TOTErrs breakdown by Name"
REPORT_META1_SORTKEYS="-k 1"
REPORT_META1=(
		DI:Name:18
		DI:Size:6
		DI:Type:6
		DI:Drive:18			# == Serial
		DS:Date:10			# smartctl -x date

		DS:m_TOTErrs:4		# sum of the below

		DS:DataErrors:4		
		DS:ErrLogs:4		
		DS:ReadErrRate:4	
		DS:PendSector:6		
		DS:OfflUncorr:6		
		DS:UDMAErrors:6		
		DS:WrErrRt:6		
		DS:RTBadBlock:6
		DS:ECCErrs:6
		DS:WearoutInd:4

)

#=======================================
REPORT_META2_DESC="Drive meta (others) breakdown by Name"
REPORT_META2_SORTKEYS="-k 1"
REPORT_META2=(
		DI:Name:18
		DI:Size:6
		DI:Type:6
		DI:Drive:18			# == Serial
		DS:Date:10			# smartctl -x date

		DS:m_TOTRealloc:4	# total reallocated blocks/events
		DS:ReallocCnt:4
		DS:ReallocBlks:4

		DS:m_LifeLeft:4		# life remaining
		DS:HeliumPct:4
		DS:LifeUsed:4

		DS:m_TempWarn:4		# total overtemp time score
		DS:OverTempT:4
		DS:WarnTempT:4
		DS:CritTempT:4

		DS:m_MaxLTemp:4	 	# maximum lifetime temperature
		DS:LTempMM:4
)

#=======================================
REPORT_ALL_DESC="All drives and fields by DIR"
REPORT_ALL_SORTKEYS="-k 3"
REPORT_ALL=(
		DI:Name:18
		DI:Size:6
		DI:Drive:18			# == Serial
		DI:Status:6
		# Ugggly...  but it works.
		$(
	cat "$PROGPATH" | grep -E '^[[:space:]]*D[IS]:[^:]+:[0-9]+[[:space:]]*(#.*)?' | sed 's/#.*//' | sort | uniq | grep -v -e 'DI:Name:' -e 'DI:Size:' -e 'DI:Drive:' -e 'DI:Status:' -e 'DI:NOTES:'
		)
		DI:NOTES:20
)


#===============================================================================
# SMARTCTL PARSER
#  (and MacOSX maxwell output)

#======================================
function parse_smartx()
# Parse a smartctl -x output from stdin into the
# (caller-declared) DI associative array.
{
	dlog "${FUNCNAME[0]}($*)"
	local state=VERSION
	local SMARTCTL_VERSION=
	local IS_MAXWELL=false
	local RAWWORD=4
	local line
	while IFS= read -r line; do

#		dlog "LINE='$line'"

		# state transitions
		if [[ "$line" =~ ^===\ START\ OF\ INFORMATION\ SECTION ]]; then
			state=INFO
#			dlog "state-->$state"
			continue
		elif [[ "$line" =~ ^===\ START\ OF\ .*SMART\ DATA\ SECTION ]]; then
			state=SMARTSTATUS
#			dlog "state-->$state"
			continue
		elif [[ "$line" =~ ^SMART\ Attributes\ Data\ Structure ]]; then
			state=SMARTATTR	
#			dlog "state-->$state"
			continue
		elif [[ "$line" =~ ^SMART/Health\ Info.*NVMe\ Log\ 0x02 ]]; then
			state=SMARTATTRNVME
#			dlog "state-->$state"
			continue
		elif [[ "$line" =~ ^SCT\ Status\ Version:\  ]]; then
			state=SCTSTATUS	
#			dlog "state-->$state"
			continue
		elif [[ "$line" =~ ^Device\ Statistics\ \(GP\ Log\ 0x04 ]]; then
			state=DEVSTATS
#			dlog "state-->$state"
			continue

		# OSX/maxwell
		elif [[ "$line" =~ ^BSD\ Path:  ]]; then
			IS_MAXWELL=true
			state=INFO
			RAWWORD=4
#			dlog "state-->$state (MAXWELL)"
			continue
		elif $IS_MAXWELL; then
#			dlog "LINE='$line'"
			if [[ "$line" =~ ^Status\ is\ (.*)$ ]]; then
				parse_smart_status
				state=MAXWELLATTR
#				dlog "state-->$state"
				continue
			fi
		fi

		# parse lines based on context
		case "$state" in
		VERSION)		parse_smart_version				;;
		INFO)			parse_smart_info				;;
		SMARTSTATUS)	parse_smart_status				;;
		SMARTATTR)		parse_smart_attr				;;
		MAXWELLATTR)	parse_maxwell_attr				;;
		SMARTATTRNVME)	parse_smart_attrNVMe			;;
		SCTSTATUS)		parse_smart_SCT					;;
		DEVSTATS)		parse_smart_devstats			;;
		esac


	done
}


#======================================
function parse_smart_version()
# Parse a smartctl header with version
{
	dlog "${FUNCNAME[0]}($*)"

	if [[ "$line" =~ ^smartctl\ ([0-9a-zA-Z\.]+)\  ]]; then
		SMARTCTL_VERSION="${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Local\ Time\ is:\ +(.*) ]]; then
		# added into maxwell output preamble...
		parse_date_time "${BASH_REMATCH[1]}"
	fi
}

#======================================
function parse_smart_info()
# Parse an INFORMATION SECTION line (from various versions)
{
	dlog "${FUNCNAME[0]}($*)"
	local value

	if [[ "$line" =~ ^Vendor:\ +(.*) ]]; then
		DIupd Vendor "${BASH_REMATCH[1]}"

	# Model
	elif [[ "$line" =~ ^Device\ Model:\ +(.*) ]]; then
		DIupd Model "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Model\ Number:\ +(.*) ]]; then
		DIupd Model "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Product:\ +(.*) ]]; then
		DIupd Model "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Model:\ +(.*) ]]; then			# maxwell
		DIupd Model "${BASH_REMATCH[1]}"

	# Serial
	elif [[ "$line" =~ ^Serial\ [Nn]umber:\ +(.*) ]]; then
		DIupd Serial "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Serial:\ +(.*) ]]; then			# maxwell
		DIupd Serial "${BASH_REMATCH[1]}"

	# Firmware
	elif [[ "$line" =~ ^Firmware:\ +(.*) ]]; then
		DIupd Firmware "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Firmware\ Version:\ +(.*) ]]; then
		DIupd Firmware "${BASH_REMATCH[1]}"

	# Bytes
	elif [[ "$line" =~ ^User\ Capacity:\ +(.*)\ bytes ]]; then
		DIupd Bytes "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Namespace\ 1\ Size/Capacity:\ +(.*)\ \[.* ]]; then
		DIupd Bytes "${BASH_REMATCH[1]}"

	# Type
	elif [[ "$line" =~ ^Rotation\ Rate:\ +(.*) ]]; then
		case "${BASH_REMATCH[1]}" in
		Solid\ State\ Device)	DIupd Type "SSD" ;;
		*\ rpm)					DIupd Type "HDD" ;;
		*)						DIupd Type "UNKNOWN" ;;
		esac
	elif [[ "$line" =~ ^NVMe\ Version:\  ]]; then
		DIupd Type "NVMe"

	# Date
	elif [[ "$line" =~ ^Local\ Time\ is:\ +(.*) ]]; then
		parse_date_time "${BASH_REMATCH[1]}"
	fi
}

#======================================
function parse_smart_status()
# Parse a SMART DATA line (from various versions)
{
	dlog "${FUNCNAME[0]}($*)"
	if [[ "$line" =~ ^SMART\ overall-health\ self-assess.*:\ +(.*) ]] ; then
		DSupd SMART "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^SMART\ Health\ Status:\ +(.*) ]]; then
		DSupd SMART "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Status\ is\ (.*) ]]; then	# maxwell
		DSupd SMART "${BASH_REMATCH[1]}"
	fi

	# Fixup 
	case "$(DSget SMART)" in
	PASSED|OK|GOOD)			DSupd SMART "OK" ;;
	esac
}

#======================================
function parse_smart_attr()
# Parse a SMART ATTRIBUTE line (from various versions)
{
	dlog "${FUNCNAME[0]}($*)"
	local col

	# multi-column values:
	if   [[ "$line" =~ ^ID#\  ]]; then
		# header; parse columns save RAW_VALUE column number
		set $line
		for (( col=1; col <= $#; col++ )); do
			if [ "${!col}" == "RAW_VALUE" ]; then
				RAWWORD=$col
				break
			fi
		done
		let RAWWORD-=2	# subtract first 2 columns for matches below
		vvvlog "RAWWORD=$RAWWORD"
	elif [[ "$line" =~ ^\ \ 1\ Raw_Read_Error_Rate\ +(.*)$ ]]; then
		DSupd ReadErrRate "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^\ \ 5\ Reallocate_NAND_Blk_Cnt\ +(.*)$ ]]; then
		DSupd ReallocBlks "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^\ \ 5\ Reallocated_Sector_Ct\ +(.*)$ ]]; then
		DSupd ReallocBlks "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^\ \ 9\ Power_On_Hours\ +(.*)$ ]]; then
		DSupd PwrOnHours "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^\ 12\ Power_Cycle_Count\ +(.*)$ ]]; then
		DSupd PwrCycles "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^\ 22\ Unknown_Attribute\ +(.*)$ ]]; then
		DSupd HeliumPct "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^177\ Wear_Leveling_Count\ +(.*)$ ]]; then
		DSupd WearLvlCnt "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^183\ Runtime_Bad_Block\ +(.*)$ ]]; then
		DSupd RTBadBlock "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^184\ Error_Correction_Count\ +(.*)$ ]]; then
		DSupd ECCErrs "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^184\ End-to-End_Error\ +(.*)$ ]]; then
		DSupd ECCErrs "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^193\ Load_Cycle_Count\ +(.*)$ ]]; then
		DSupd LoadCycles "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^194\ Temperature_Celsius\ +(.*)$ ]]; then
		DSupd Temp "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^196\ Reallocated_Event_Count\ +(.*)$ ]]; then
		DSupd ReallocCnt "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^197\ Current_Pend[^\ ]+\ +(.*)$ ]] ; then
		DSupd PendSector "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^198\ Offline_Uncorrectable\ +(.*)$ ]]; then
		DSupd OfflUncorr "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^199\ .*CRC_Error_Count\ +(.*)$ ]]; then
		DSupd UDMAErrors "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^202\ Percent_Lifetime_Remain\ +(.*)$ ]]; then
		# Crucial-only? RAW is complement
		DSupd LifeUsed "$(get_word $RAWWORD "${BASH_REMATCH[1]}")%"
	elif [[ "$line" =~ ^206\ Write_Error_Rate\ +(.*)$ ]]; then
		DSupd WrErrRt "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^233\ Media_Wearout_Indicator\ +(.*)$ ]]; then
		DSupd WearoutInd "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^235\ POR_Recovery_Count\ +(.*)$ ]]; then
		DSupd PwrOffRcvy "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	fi
}

#======================================
function parse_maxwell_attr()
# Parse a SMART ATTRIBUTE line (from OSX/Maxwell)
{
	dlog "${FUNCNAME[0]}($*)"
	local col

	# multi-column values:
	if [[ "$line" =~ ^\(\ \ 1\)\ Raw\ Read\ Error\ Rate\ +(.*)$ ]]; then
		DSupd ReadErrRate "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^\(\ \ 9\)\ Power-On\ Hours\ Count\ \*\*\ +(.*)$ ]]; then
		DSupd PwrOnHours "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^\(\ 12\)\ Device\ Power\ Cycle\ Count\ +(.*)$ ]]; then
		DSupd PwrCycles "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^\(193\)\ Load/Unload\ Cycle\ Count\ +(.*)$ ]]; then
		DSupd LoadCycles "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^\(194\)\ Device\ Temperature\ +(.*)$ ]]; then
		DSupd Temp "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^\(196\)\ Reallocation\ Event\ Count\ +(.*)$ ]]; then
		DSupd ReallocCnt "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^\(197\)\ Current\ Pending\ Sector\ Count\ +(.*)$ ]] ; then
		DSupd PendSector "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^\(198\)\ Off-Line\ Scan\ Uncorrectable\ Sector\ Count\ +(.*)$ ]]; then
		DSupd OfflUncorr "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^\(199\)\ Ultra\ DMA\ CRC\ Error\ Count\ +(.*)$ ]]; then
		DSupd UDMAErrors "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^\(200\)\ Write\ Preamp\ Errors\ +(.*)$ ]]; then
		DSupd WrErrRt "$(get_word $RAWWORD "${BASH_REMATCH[1]}")"
	fi
}


#======================================
function parse_smart_attrNVMe()
# Parse a SMART ATTRIBUTE line from NVMe Log 0x02
{
	dlog "${FUNCNAME[0]}($*)"
	# multi-column values:
	if [[ "$line" =~ ^Percentage\ Used:\ +(.*)$ ]]; then
		DSupd LifeUsed "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Critical\ Warning:\ +(.*)$ ]]; then
		DSupd CritWarn "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Temperature:\ +(.*)\ Celsius$ ]]; then
		DSupd Temp "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Power\ On\ Hours:\ +(.*)$ ]]; then
		DSupd PwrOnHours "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Power\ Cycles:\ +(.*)$ ]]; then
		DSupd PwrCycles "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Media\ and\ Data\ Integrity\ Errors:\ +(.*)$ ]]; then
		DSupd DataErrors "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Error\ Information\ Log\ Entries:\ +(.*)$ ]]; then
		DSupd ErrLogs "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Warning\ Comp\.\ Temperature\ Time:\ +(.*)$ ]]; then
		DSupd WarnTempT "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Critical\ Comp\.\ Temperature\ Time:\ +(.*)$ ]]; then
		DSupd CritTempT "${BASH_REMATCH[1]}"
	fi
}

#======================================
function parse_smart_SCT()
{
	dlog "${FUNCNAME[0]}($*)"
	# Temps
	if [[ "$line" =~ ^Current\ Temperature:\ +(.*)\ Celsius$ ]]; then
		DSupd Temp "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Power\ Cycle\ Min/Max\ Temperature:\ +(.*)\ Celsius$ ]]; then
		DSupd PCTempMM "${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Lifetime\ +Min/Max\ Temperature:\ +(.*)\ Celsius$ ]]; then
		DSupd LTempMM "${BASH_REMATCH[1]}"
	fi
}

#======================================
function parse_smart_devstats()
{
	dlog "${FUNCNAME[0]}($*)"
	if [[ "$line" =~ ^0x05\ \ 0x050\ +(.*)$ ]]; then
		DSupd OverTempT "$(get_word 2 "${BASH_REMATCH[1]}")"
	# WD Vendor specific that keep changing; keep an eye on them...
	elif [[ "$line" =~ ^0xff\ \ 0x040\ +(.*)$ ]]; then
		DSupd Dev040 "$(get_word 2 "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^0xff\ \ 0x048\ +(.*)$ ]]; then
		DSupd Dev048 "$(get_word 2 "${BASH_REMATCH[1]}")"
	elif [[ "$line" =~ ^0xff\ \ 0x080\ +(.*)$ ]]; then
		DSupd Dev080 "$(get_word 2 "${BASH_REMATCH[1]}")"
	fi
}

#======================================
function parse_date_time()
# Parse a Unix format date string and set DS:Date
{
	dlog "${FUNCNAME[0]}($*)"
	local value
	set - $*
	value="$( date --date="$2 $3 $5" +%Y/%m/%d )"
	DSupd Date "$value"
}


#===============================================================================
# INFO.txt & STATS.txt PARSERS & GENERATORS

INFO_FIELDS=(
	Name			# My name for the drive <hostname>-<name>, etc
	Serial			# Serial number printed on the drive
	SysID			# Serial that the OS reports; might be different; see ACTIVE
	Model			# Model that smartctl reports
	ProductName		# friendlier Model; defaults to Model
	Firmware		# Firmware that smartctl reports
	Tran			# Transport (sata, usb, etc) reported by OS
	Type			# HDD | SSD | NVMe
	Size			# friendly size
	Bytes			# with commas
#	Dev				# active device; (OMIT: it's volatile; can change on reboot)
	Status			# ACTIVE, STOWED, ...
	Hostname		# short hostname
	HostOS			# LNX | WIN | MAC
	StowDate		# yyyy/mm/dd
	SmartctlOpts	# options to smartctl -x, usually a -d <device>
	Location		# my location codes
	NOTES			# my notes; possibly multi-line
)

INFO_FIELDS_MANDATORY=(
	Name
	Serial
	Model
	Type
	Size
	Bytes
	Status
	Location
	NOTES
)

#======================================
function parse_INFO()
# Parse an INFO.txt file info into DRIVE_INFO object
{
	dlog "${FUNCNAME[0]}($*)"
	local drive="$1"; shift
	local key value is_note
	if [ ! -r "$drive/INFO.txt" ]; then
		log "$drive: missing INFO.txt\n"
		return 1
	fi
	is_note=false
	while IFS= read -r line ; do
		if $is_note; then
			#value="$value"$'\n'"$line"
			value="$value\\n$line"
		else
			key="${line%%:*}"
			value="${line#*:}"
			value="${value#	}"		# remove leading tab
			# log "key='$key' value='$value'"
			if [ "$key" == "NOTES" ]; then
				is_note=true
			else
				DIupd "$key" "$value"
			fi
		fi
	done < <( cat "$drive/INFO.txt" | sed -e 's/#.*//' -e '/^\s*$/d' )
	if $is_note; then
		DIupd NOTES "$value"
	fi
}

#======================================
function generate_INFO()
# Generate an INFO.txt file to stdout from current DRIVE_INFO.
{
	dlog "${FUNCNAME[0]}($*)"
	local k val


	printf "# vim: ts=24\n"

	# First mandatory fields
	for k in "${INFO_FIELDS[@]}"; do
		val="$(DIget "$k")"

		# Special cases
		if [ "$k" == 'SysID' -a "$val" == "$(DIget Serial)" ]; then
			continue	# Omit SysID if same as Serial
		elif [ "$k" == 'ProductName' -a "$val" == "$(DIget Model)" ]; then
			continue	# Omit ProductName if same as Model
		elif [ "$k" == 'NOTES' ]; then
			val="$(echo "$val" | sed 's/\\n/\n/g' )"		# expand \n
		fi
		if [ -z "$val" ]; then
			if ! in_array INFO_FIELDS_MANDATORY "$k"; then
				continue	# omit optional fields if empty
			fi
		fi

		printf "%s:\t%s\n" "$k" "$val"
	done
}

#======================================
function update_INFO()
# Load/Merge information from ACTIVE into DRIVE_INFO object
# If FORCE is nonempty, updated info replaces any existing.
{
	dlog "${FUNCNAME[0]}($*)"
	local drive="$1"; shift
	local sysid dev tran model host serial
	local bytes Xbytes size
	local serial
	local FORCE="$FORCE"

	# sanity check
	serial="$(DIget Serial)"
	if [ "$serial" != "$drive" ]; then
		logwarn "$drive: INFO.txt Serial MISMATCH: '$serial'"
	fi
	DIupd Drive "$drive"

	# Make sure DRIVE_INFO has a 'SysID' property
	sysid="$(DIget SysID)"
	if [ -z "$sysid" ]; then
		sysid="$serial"
		DIupd SysID "$sysid"
	fi

	# Get/set the device & tran if active
	if is_ACTIVE "$sysid"; then
		host="$(get_ACTIVE "$sysid" Hostname)"
		if [ "$host" != "$(DIget Hostname)" ]; then
			logwarn "update_INFO: $drive: Hostname mismatch:"
			logpf "  DRIVE_INFO[Hostname]='$(DIget Hostname)'\n"
			logpf "  ACTIVE[$sysid].Hostname='$host'\n"
			DIdump
			dump_ACTIVE
			exit 1
		fi
		DIupd Dev	"$(get_ACTIVE "$sysid" Dev)"
		DIupd Tran	"$(get_ACTIVE "$sysid" Tran)"
		DIupd Model  "$(get_ACTIVE "$sysid" Model)"
	fi

	# The friendly size
	bytes="$(echo "$(DIget Bytes)" | tr -d , )"
	if [ -n "$bytes" ]; then
		Xbytes="$(echo "scale=0; $bytes/1000/1000/1000/1000" | bc )"
		if (( Xbytes > 0 )); then
			size="${Xbytes}TB"
		else
			Xbytes="$(echo "scale=0; $bytes/1000/1000/1000" | bc )"
			if (( Xbytes > 0 )); then
				size="${Xbytes}GB"
			else
				Xbytes="$(echo "scale=0; $bytes/1000/1000" | bc )"
				size="${Xbytes}MB"
			fi
		fi
		DIupd Size "$size"
	else
		vvlog "$drive: missing or empty 'Bytes' property."
	fi

	# Make sure DRIVE_INFO has a 'ProductName' property
	if [ -z "$(DIget ProductName)" ]; then
		DIupd ProductName "$(DIget Model)"
	fi

}


#======================================
function parse_STATS()
# Parse the last line of an STATS.txt file into DRIVE_STATS object
{
	dlog "${FUNCNAME[0]}($*)"
	local drive="$1"; shift
	local line fields values i val
	if [ ! -r "$drive/STATS.txt" ]; then
		vlog "$drive: missing STATS.txt"
		return 1
	fi
	line="$(grep -E $'^#\tDate\t' "$drive/STATS.txt")"
	fields=( ${line:1} )		# get rid of leading '#'

	values=( $(tail -1 "$drive/STATS.txt") )
	for (( i=0; i < ${#values[@]}; i++ )); do
		val="${values[$i]}"
		if [ "$val" = '-' ]; then val=""; fi
		DSupd "${fields[$i]}" "$val"
	done
}

#======================================
function generate_STATS_header()
# Generate a STATS.txt file header to stdout
{
	dlog "${FUNCNAME[0]}($*)"
	local k w
	printf "# %s\n" "$(DIget Serial)"
	printf "# ws 180\n"

	# Field widths
	printf "# vim: nowrap:vts=4,12,8"
	for k in $(DSlist) ; do
		if is_skip_STATS_field "$k"; then continue; fi
		if DSis_set "$k"; then
			w="${#k}"
			let w+=2		# 2 spaces between heading cols
			if (( w < 8 )); then w=8; fi	# min 8
			printf ",%s" "$w"
		fi
	done
	printf "\n"

	printf "#\tDate\tSMART"
	for k in $(DSlist) ; do
		if is_skip_STATS_field "$k"; then continue; fi
		DSis_set "$k" && printf "\t%s" "$k"
	done
	printf "\n"
}


#======================================
function generate_STATS_line()
# Generate a STATS.txt line to stdout from current DRIVE_STATS.
{
	dlog "${FUNCNAME[0]}($*)"
	local k val

	printf "\t%s" "$(DSget Date)"
	printf "\t%s" "$(DSget SMART)"
	for k in $(DSlist); do
		if is_skip_STATS_field "$k"; then continue; fi
		if ! DSis_set "$k"; then continue; fi
		val="$(DSget "$k")"
		if [ -z "$val" ]; then val="-"; fi	# ensure it's non-white for parse
		printf "\t%s" "$val"
	done
	printf "\n"
}


#======================================
function is_skip_STATS_field()
{
	local k="$1"
	local ret=1
	if [[ "$k" =~ ^m_ ]]; then ret=0; 
	elif [ "$k" = "Date" ]; then ret=0;
	elif [ "$k" = "SMART" ]; then ret=0;
	fi
	return $ret
}


#===============================================================================
# HELPER FUNCTIONS


#======================================
function get_word()
# get_word <n> <str>
# Return word <n> from string
{
	local pos="$1"; shift
	set -- $*
	echo "${!pos}"
}


#======================================
function mkident()
# mkident <str>
# Make <str> into a valid identifier by replacing illegal chars with _.
{
	printf "%s" "$1" | tr -C '[:alnum:]' '_'
}


#======================================
function sortkeyincr()
# sortkeyincr <arg> ...
#  Increment all sort key fields in <arg> ...
#  args must use the form -k KEYDEF (rather than --key=KEYDEF)
{
	local state=START
	local i=0
	local defs=()
	local outstr def suffix field first

	outstr=""
	for v in "$@"; do
		let i+=1
		case "$state" in
		START)
			if [ "$v" == '-k' ]; then
				state=KEYDEF
				outstr+=" -k"
			else
				logerr "Bad SORTKEY arg $i: '$v'"
				return
			fi
			;;

		KEYDEF)
			defs=( ${v//,/ } )		# split at ,
			first=true
			for def in "${defs[@]}"; do
				suffix="${def##+([0-9])}"		# extglob reqd
				field="${def%%$suffix}"	
				let field+=1					# increment
				if $first; then
					outstr+=' '
					first=false
				else
					outstr+=','
				fi
				outstr+="${field}${suffix}"
			done
			state=START
			;;

		esac
	done
	printf "%s\n" "$outstr"
}


#======================================
function rssh()
# rssh <cmd> ...
# Remote ssh:  execute SSH <cmd>
{
	dlog "${FUNCNAME[0]}($*)"
	vvlog ">> $SSH $*"
	"$SSH" "$@"
	vvlog "<< DONE $SSH $*"
	return $?
}


#======================================
function is_remote()
# Return 0 if current DRIVE_INFO is an active remote drive on a host that
# is up and ready.
# Return 2 if it is an active remote drive, but the host is not responding
# or REMOTE operation is not enabled.
# Otherwise, (it is local or STOWED) , return 1.

{
	dlog "${FUNCNAME[0]}($*)"
	local host="$(DIget Hostname)"
	local drive="$(DIget Drive)"

	if [ "$(DIget Status)" != "ACTIVE" ]; then return 1; fi # not ACTIVE
	if [ -z "$host" ]; then return 1; fi				# no Hostname defined
	if [ "$host" == "$HOSTNAME" ]; then return 1; fi	# we are the local host

	if	[ -z "$EXEC_REMOTE" ]; then
		# REMOTE not enabled
		vlog "$drive: use -r to enable remote request."
		return 2
	fi
	vvlog "Checking if remote host '$host' is up..."
	if ! net_check_host "$host"; then
		log "$drive: remote host '$host' not responding."
		return 2
	fi

	return 0		# all good for remote
}

#======================================
function op_pre()
# Perform any defined OP_$OP_PRE function
{
	dlog "${FUNCNAME[0]}($*)"
	if [ "$(type -t OP_${OP}_PRE||true)" = 'function' ]; then
		OP_${OP}_PRE
	fi

	if ! [ "$(type -t OP_${OP}||true)" = 'function' ]; then
		logerr "INTERNAL: No such DRIVE OPERATION function: OP_$OP"
		exit 1
	fi
}

#======================================
function op_driveloop()
# Loop over DRIVES and perform OP_$OP on each.
{
	dlog "${FUNCNAME[0]}($*)"
	local drive cmd val
	local flog=vvlog
	if [ -n "$REPORT" ]; then flog=vvvlog; fi


	for drive in "${DRIVES[@]}"; do
		if [ ! -d "$drive" ]; then
			log "$drive:  no such drive directory; skipping"
			continue
		fi

		DIreset
		DSreset
		# Load DRIVE_INFO for <drive>
		vvlog "parse_INFO $drive"
		parse_INFO "$drive"

		# Filter by status 
		if [ -n "$STATUS_FILTER" -a \
			"$(DIget Status)" != "$STATUS_FILTER" ]; then
			$flog "Skipping $drive: 'Status' != $STATUS_FILTER"
			continue
		fi
		# Filter by Hostname
		if [ -n "$HOST_FILTER" -a \
			"$(DIget Hostname)" != "$HOST_FILTER" ]; then
			$flog "Skipping $drive: 'Hostname' != $HOST_FILTER"
			continue
		fi
		# Filter by HostOS 
		if [ -n "$OS_FILTER" -a \
			"$(DIget HostOS)" != "$OS_FILTER" ]; then
			$flog "Skipping $drive: 'HostOS' != $OS_FILTER"
			continue
		fi

		# merge any INFO (needs to be done before load_STATS)
		vvlog "update_INFO $drive"
		update_INFO "$drive"

		# Load DRIVE_STATS
		vvlog "load_STATS $drive"
		load_STATS "$drive"

		# Filter by STATS
		if [ -n "$ERR_FILTER" ]; then
			val="$(DSget m_TOTErrs)"
			if [ -z "$val" -o "$val" = 0 ]; then
				$flog "Skipping $drive: m_TOTErrs = 0"
				continue
			fi
		fi

		OP_${OP} "$drive"

		if [ -n "$DO_DUMP" ]; then
			logpf "#============ '$drive' \n"
			logpf "DRIVE_INFO[]:\n"
			DIdump
			logpf "DRIVE_STATS[]:\n"
			DSdump
		fi

	done
}


#===============================================================================
# DRIVE_INFO and DRIVE_STATS objects

_USE_AARRAY=true
if $_USE_AARRAY; then
	dlog "ASSOCIATIVE ARRAYS: Using CJRLIB::aarray functions."
	AARRAY_NO_NATIVE=true
	# DRIVE_INFO
	function DIinit()		{ aa_create DRIVE_INFO ; }
	function DIreset()		{ DIinit; }
	function DIset()		{ aa_set DRIVE_INFO "$@" ; }
	function DIget()		{ aa_get DRIVE_INFO "$@" ; }
	function DIis_set()		{ aa_is_set DRIVE_INFO "$@" ; }
	function DIlist()		{ aa_list DRIVE_INFO ; }
	function DIdump()		{ aa_dump DRIVE_INFO 1>&2 ; }
	# DRIVE_STATS
	function DSinit()		{ aa_create DRIVE_STATS ; }
	function DSreset()		{ DSinit; }
	function DSset()		{ aa_set DRIVE_STATS "$@" ; }
	function DSget()		{ aa_get DRIVE_STATS "$@" ; }
	function DSis_set()		{ aa_is_set DRIVE_STATS "$@" ; }
	function DSlist()		{ aa_list DRIVE_STATS ; }
	function DSdump()		{ aa_dump DRIVE_STATS 1>&2 ; }
else
	dlog "ASSOCIATIVE ARRAYS: Using native bash associative arrays"
	# DRIVE_INFO
	function DIinit()		{ declare -gA DRIVE_INFO=() ; }
	function DIreset()		{ DRIVE_INFO=() ; }
	function DIset()		{ DRIVE_INFO[$1]="$2" ; }
	function DIget()		{ printf "%s" "${DRIVE_INFO[$1]}" ; }
	function DIis_set()		{ [ -n "${DRIVE_INFO[$1]+XX}" ]; }
	function DIlist()		{ printf "%s" "${!DRIVE_INFO[@]}"; }
	function DIdump() { local key ; for key in "${!DRIVE_INFO[@]}"; do
		printf >&2 "  %-20s : '%s'\n" "$key" "${DRIVE_INFO[$key]}" ; done ; }
	# DRIVE_STATS
	function DSinit()		{ declare -gA DRIVE_STATS=() ; }
	function DSreset()		{ DRIVE_STATS=() ; }
	function DSset()		{ DRIVE_STATS[$1]="$2" ; }
	function DSget()		{ printf "%s" "${DRIVE_STATS[$1]}" ; }
	function DSis_set()		{ [ -n "${DRIVE_STATS[$1]+XX}" ]; }
	function DSlist()		{ printf "%s" "${!DRIVE_STATS[@]}"; }
	function DSdump() { local key ; for key in "${!DRIVE_STATS[@]}"; do
		printf >&2 "  %-20s : '%s'\n" "$key" "${DRIVE_STATS[$key]}" ; done ; }
fi

#======================================
# DI & DS update
function DIupd() { ArrayUpdate DI "$@" ; }
function DSupd() { ArrayUpdate DS "$@" ; }
#======================================
function ArrayUpdate()
# ArrayUpdate <array> <key> <val>
#   Updates key=val in <array> with error checking and reporting.
# 	<array> is either DI or DS.
{
	dlog "${FUNCNAME[0]}($*)"
	local arr="$1"; shift
	local key="$1"; shift
	local val="$1"; shift
	local prev
	local Aname Aset Aget isset
	local FORCE="$FORCE"

	case "$arr" in
	DI)
		Aname=DRIVE_INFO
		Aset=DIset
		Aget=DIget
		isset=DIis_set
		;;
	DS)
		Aname=DRIVE_STATS
		Aset=DSset
		Aget=DSget
		isset=DSis_set
		FORCE=true
		;;
	*)	log "DISupdate: unknown array: $arr"
		exit 1
		;;
	esac

	# clean up val
	val="$(string_trim "$val")"

	if ! $isset "$key"; then
		# not yet set; do it
		prev="$($Aget "$key")"
		if [ -n "$prev" ]; then log "XXXXX: prev=$prev"; fi
		vvvlog "${arr}upd: $Aname[$key] UNSET --> '$val'"
		$Aset "$key" "$val"
	else
		# already set... get prev
		prev="$($Aget "$key")"
		if [ -z "$prev}" ]; then
			# was empty; silently set new value
			vvvlog "${arr}upd: $Aname[$key] <empty> --> '$val'"
			$Aset "$key" "$val"
		elif [ "$val" == "$prev" ]; then
			# already set to $val; silently do nothing
			:
		else
			# changed value
			if [ -z "$FORCE" ]; then
				vvlog "IGNORING: $Aname[$key] change '$prev' -> '$val'"
			else
				vvlog "${arr}upd: $Aname[$key] CHANGED '$prev' -> '$val'"
				$Aset "$key" "$val"
			fi
		fi
	fi
}

#======================================
function getDSval()
# getDSval <field>
# Return a validated integer value for DRIVE_STATS <field>
{
	local key="$1"; shift
	local val="$(DSget "$key")"
	val="${val//,/}"	# get rid of commas
	if [ -z "$val" ]; then
		val=0
	elif [[ "$val" =~ ^-?[0-9]+$ ]]; then
		:		# val is good
	else
		logerr "getDSval: Illegal value for DS::$key: $val"
		val=0	# invalid
	fi
	echo $val
}



#===============================================================================
# ACTIVE object
#  ACTIVE is an assoc. array of (Hostname, Dev, Tran, Model) tuples by SysID

declare -a ACTIVE_SysID=()
declare -a ACTIVE_Hostname=()
declare -a ACTIVE_Dev=()
declare -a ACTIVE_Tran=()
declare -a ACTIVE_Model=()

#======================================
function init_ACTIVE()
# init_ACTIVE
# Initialize ACTIVE datastructures.
{
	ACTIVE_SysID=()
	ACTIVE_Hostname=()
	ACTIVE_Dev=()
	ACTIVE_Tran=()
	ACTIVE_Model=()
}

#======================================
function is_ACTIVE()
# is_ACTIVE sysid
# Returns 0 if there exists an ACTIVE entry for <sysid>.
{
	dlog "${FUNCNAME[0]}($*)"
	local sysid="$1"; shift
	local _sysid="$(mkident "$sysid")"
	local var="ACTIVE_$_sysid"
	[ -n "${!var}" ]
}

#======================================
function list_ACTIVE()
# list_ACTIVE
# Lists all sysids in ACTIVE.
{
	local sysid
	local idx
	for (( idx=0; idx<${#ACTIVE_SysID[@]}; idx++ )); do
		printf "%s\n" "${ACTIVE_SysID[$idx]}"
	done
}

#======================================
function get_ACTIVE()
# get_ACTIVE sysid key
# Return the value for <key> for ACTIVE drive with <sysid>.
{
#	dlog "${FUNCNAME[0]}($*)"
	local sysid="$1"; shift
	local key="$1"; shift
	local _sysid="$(mkident "$sysid")"
	local var="ACTIVE_$_sysid"
	local idx="${!var}"

	if [ -z "$idx" ]; then
		logwarn "ACTIVE[$sysid]: undefined"
		return 1
	fi
	if [ "${ACTIVE_SysID[$idx]}" != "$sysid" ]; then
		logwarn "ACTIVE[$sysid]: sysid hash collision? for index $idx:"
		dump_ACTIVE
	fi

	var="ACTIVE_${key}[$idx]"
	printf "%s" "${!var}"
}

#======================================
function set_ACTIVE()
# set_ACTIVE <sysid> <host> <dev> <tran> <model>
# Sets ACTIVE entry for <sysid> : (host,dev,tran,model)
{
	dlog "${FUNCNAME[0]}($*)"
	local sysid="$1"; shift
	local host="$1"; shift
	local dev="$1"; shift
	local tran="$1"; shift
	local model="$1"; shift
	local _sysid="$(mkident "$sysid")"
	local var="ACTIVE_$_sysid"
	local idx="${!var}"

#	if is_ACTIVE "$sysid"; then
	if [ -n "$idx" ]; then
		logwarn "set_ACTIVE[$sysid] already exists; skipping"
		if [ -n "$DEBUG" ]; then dump_ACTIVE; fi
		return 1
	fi

	# Add entry
	idx=${#ACTIVE_SysID[@]}
	eval "$var=$idx"			# set sysid association/index variable

	ACTIVE_SysID[$idx]="$sysid"
	ACTIVE_Hostname[$idx]="$host"
	ACTIVE_Dev[$idx]="$dev"
	ACTIVE_Tran[$idx]="$tran"
	ACTIVE_Model[$idx]="$model"
}

#======================================
function dump_ACTIVE()
# Dump all the ACTIVE arrays
{
	dlog "${FUNCNAME[0]}($*)"
	local sysid idx
	local fmt="%4s %-10s %-12s %-8s %-30s %-s"
	printf >&2 "$fmt\n" '# N' ' Host' 'Dev' 'Tran' 'Model' 'SysID'
	idx=0
	for sysid in $(list_ACTIVE) ; do
		printf >&2 "$fmt\n"							\
			"$idx"								\
			"$(get_ACTIVE "$sysid" Hostname)"	\
			"$(get_ACTIVE "$sysid" Dev)"		\
			"$(get_ACTIVE "$sysid" Tran)"		\
			"$(get_ACTIVE "$sysid" Model)"		\
			"$sysid"
		let idx+=1
	done
}

#======================================
function load_ACTIVE()
# Load active drive info into the ACTIVE datastructure by sysid.
# sysid is normally the drive serial number, but might not;
# it could be the serial number of e.g. the SATA-USB bridge chip, etc.
{
	dlog "${FUNCNAME[0]}($*)"
	local cmd=()
	local dev tran sysid model
	local n dec hex letter
	local done

	# reset globals
	init_ACTIVE
	case "$SYS_OS" in
	LNX)
		cmd=( "$LSBLK" -o NAME,TRAN,SERIAL,MODEL )
		dlog "${cmd[*]}"
		while read dev tran sysid model; do
			set_ACTIVE "$sysid" "$HOSTNAME" "/dev/$dev" "$tran" "$model"
		done < <( "${cmd[@]}" | grep -vE '^(\||`)'|tail +2 )
		;;
	WIN)
		# NB: wmic columns are alphabetical regardless of order of properties
		cmd=( "$WMIC" diskdrive get DeviceID,InterfaceType,Model,SerialNumber )
		dlog "${cmd[*]}"
		while read wdev tran rest; do

			# XXX: hope dev, tran, and sysid have no spaces
			sysid="${rest##* }"		# sysid is just the last word
			model="${rest%%$sysid}"	# strip trailing sysid to get model
			model="${model%"${model##*[![:space:]]}"}"		# rtrim()
#			sysid="${sysid##.}"		# get rid of trailing dot...?  NO


			# convert Windows PHYSICALDRIVE<n> to smartctl /dev/sdX
			n="${wdev##\\.PHYSICALDRIVE}"
			dec=$(( n + $( printf "%d" \'a) ))		# [0-9] --> [a-j], etc
			hex="$(printf "%x" "$dec" )"
			letter="$(printf "\x$hex")"
			dev="/dev/sd$letter"

			if [ -n "$DEBUG" ]; then
				vvlog "WMIC: wdev   = '$wdev'\n"
				vvlog "WMIC: tran   = '$tran'\n"
				vvlog "WMIC: rest   = '$rest'\n"
				vvlog "WMIC: sysid  = '$sysid'\n"
				vvlog "WMIC: model  = '$model'\n"
				vvlog "WMIC: n      = '$n'\n"
				vvlog "WMIC: dec    = '$dec'\n"
				vvlog "WMIC: hex    = '$hex'\n"
				vvlog "WMIC: letter = '$letter'\n"
				vvlog "WMIC: dev    = '$dev'\n"
			fi

			set_ACTIVE "$sysid" "$HOSTNAME" "$dev" "$tran" "$model"
		done < <( "${cmd[@]}" | tr -d '\015' | sed '/^$/d' | tail +2 )

		;;
	MAC)
		done=false
		while read line; do
			if [[ "$line" =~ ^BSD\ Path:\ *(.*) ]]; then
				dev="${BASH_REMATCH[1]}"
			elif [[ "$line" =~ ^Serial:\ *(.*) ]]; then
				sysid="${BASH_REMATCH[1]}"
			elif [[ "$line" =~ ^Model:\ *(.*) ]]; then
				model="${BASH_REMATCH[1]}"
				done=true
			fi
			if $done; then
				set_ACTIVE "$sysid" "$HOSTNAME" "$dev" "sata" "$model"
				done=false
			fi
		done < <( maxwell -r 2>/dev/null| grep -e ^BSD -e ^Serial -e ^Model )
		;;
	*)
		logwarn "load_ACTIVE: Unknown SYS_OS: '$SYS_OS'"
		;;
	esac

}


#===============================================================================
# UTILITY OPERATIONS


#======================================
# UTIL_MOVEX
UTIL_MOVEX_DESC="Move *.smartx files in CWD to their appropriate folders,"
UTIL_MOVEX_DESC+=$'\nlooking up their basename as the drive\'s INFO::Name.'

function UTIL_MOVEX()
{
	dlog "${FUNCNAME[0]}($*)"
	local f
	shopt -s nullglob		# don't match anything if empty
	for f in *.smartx; do
		util_move_smartx "$f"
	done
}

function util_move_smartx()
# util_move_smartx <f>
# Move .smartx file <f> into its appropriate drive folders with 
# timestamp
{
	dlog "${FUNCNAME[0]}($*)"
	local f="$1"; shift
	local f name drive basename datestr timestamp newname

	basename="${f%.smartx}"

	# Check if it has an existing datestr
	name="${basename%.*}"
	if [ "$name" = "$basename" ]; then
		# nope
		datestr=
	else
		# maybe; check if it looks valid
		datestr="${basename##$name.}"
		if [ ${#datestr} -ne 8 -o  \
			-n "$( printf "%s" "$datestr" | tr -d '[0-9]' )" ]; then
			# doesn't look like a valid datestr; put back together
			name="${name}.${datestr}"
			datestr=
		fi
	fi
	if [ -z "$datestr" ]; then
		# create a new datestr from file's timestamp
		timestamp="$( stat -c %y "$f")"
		datestr="$( date -d "$timestamp" +%Y%m%d )"
	fi

	# find the drive with the given name:
	if ! drive="$( grep -E "^Name:\s+$name" */INFO.txt )" ; then
		log "Can't determine drive directory for '$name'"
		return 1
	fi
	drive="${drive%%/*}"
	if [ -z "$drive" ]; then
		log "Can't determine drive directory for '$name'"
		return 1
	fi

	newname="$name.$datestr.smartx"

	$VEXEC mv  -i "$f"  "$drive/$newname"
}

#======================================
# UTIL_INFO
UTIL_INFO_DESC="Parse a .smartx from stdin into an INFO.txt to stdout."
function UTIL_INFO()
{
	dlog "${FUNCNAME[0]}($*)"
	parse_smartx < <( tr -d '\015' )
	update_INFO "$(DIget Serial)"
	generate_INFO
}


#======================================
# UTIL_STATS
UTIL_STATS_DESC="Parse a .smartx from stdin into a STATS.txt line to stdout."
function UTIL_STATS()
{
	dlog "${FUNCNAME[0]}($*)"
	parse_smartx < <( tr -d '\015' )
	if [ -n "$DO_STATS_HEADER" ]; then
		generate_STATS_header
	fi
	generate_STATS_line
}

#===============================================================================
# STATS/SMARTX LOAD functions

#======================================
function load_STATS()
# load_STATS <drive>
# Load DRIVE_STATS for <drive>
# based on STAT_MODE.
{
	dlog "${FUNCNAME[0]}($*)"
	local drive="$1"; shift
	local ret

	case "$STATS_MODE" in
	NONE)
		dlog "load_STATS: case NONE"
		:
		;;
	LINE)
		# load most recent (last) line from STATS.txt
		dlog "load_STATS: case LINE"
		vvlog "parse_STATS \"$drive\""
		parse_STATS "$drive"
		ret=$?
		;;
	FILE)
		dlog "load_STATS: case FILE"
		# parse most recent .smartx file
		fname="$(get_recent_smartx "$drive")"
		if [ -z "$fname" ]; then
			vlog "load_STATS: $drive:  No .smartx files found"
			return 1
		fi
		vvlog "parse_smartx < <( cat \"$fname\" | tr -d '\015' )"
		parse_smartx < <( cat "$fname" | tr -d '\015' )
		ret=$?
		;;
	DISCARD)
		dlog "load_STATS: case DISCARD"
		# do a smartctl -x and load it
		vvlog "parse_smartx < <( exec_SMARTX \"$drive\" )"
		parse_smartx < <( exec_SMARTX "$drive" )
		ret=$?
		;;
	SAVE)
		# do an OP_SMARTX in WRITE mode
		if OUTMODE=WRITE  OP_SMARTX "$drive"; then
			vvlog "parse_smartx < \"$SMARTX_FNAME\""
			if [ -n "$DRYRUN" ]; then
				log "parse_smartx < \"$SMARTX_FNAME\""
			else
				vvlog "parse_smartx < \"$SMARTX_FNAME\""
				parse_smartx < "$SMARTX_FNAME"
			fi
		fi
		ret=$?
		;;
	esac

	# create meta entries
	set_STATS_meta

	return $ret
}

#======================================
function get_recent_smartx()
# get_recent_smartx <drive>
# Return the filename of the most recent .smartx file in the current
# directory.
{
	dlog "${FUNCNAME[0]}($*)"
	local drive="$1"; shift
	local fname
	fname="$(ls -1t "$drive"/*.smartx 2>/dev/null | head -1)"
	if [ -z "$fname" ]; then
		return 1
	fi
	echo -n "$fname"
}

#======================================
function exec_SMARTX()
# exec_SMARTX <drive>
# Execute a smartctl -x for the current drive on its host to stdout.
{
	dlog "${FUNCNAME[0]}($*)"
	local drive="$1"; shift
	local drive host hostos
	local sysid dev cmd

	host="$(DIget Hostname)"
	hostos="$(DIget HostOS)"
	if is_remote "$host"; then
		# execute remote query and collect response into local vars
		cmd=()
		case "$hostos" in
		LNX|MAC)
			# Use -tt to force allocation of pseudo-tty for sudo passwd prompt
			# NB: this forces stderr to combine with stdout!
			# cmd+=( -tt )
			cmd+=( -tt )
			NEEDS_CLEANING=true		# stderr is mixed into stdout with -tt
			printf >&2 "$host: Enter [sudo] password for $USER:\n" 
			;;
		esac

		cmd+=( "$host" "$DRIVE_INFO_PATH" "${REM_OPTS[@]}" )
		cmd+=( -x "$drive" )	# stdout SMARTX query

		# Do the remote command (to stdout)
		if [ -z "$DRYRUN" -o  -n "$PASS_REMOTE_FLAGS" ]; then
			rssh "${cmd[@]}" | tr -d '\015'
		else
			log "rssh ${cmd[*]} | tr -d '\015'"
		fi

		ret=$?
		if [ $ret -ne 0 ]; then
			vlog "$host:$drive: remote -x command returned non-zero: $ret"
		fi
		# and return
		return $ret

	elif [ $? == 2 ]; then
		# remote, but disabled or not responding; fail
		return 1
	fi

	# Not remote; do it locally
	dev="$(DIget Dev)"
	sysid="$(DIget SysID)"
	if [ -z "$dev" -o "$dev" = 'OFFLINE' ]; then
		log "$drive: no online device found for SysID='$sysid'"
		return 1
	fi

	# Construct the command
	cmd=()
	case "$SYS_OS" in
	LNX|WIN)
		if [ "$SYS_OS" == LNX ]; then cmd+=( sudo ); fi
		cmd+=( smartctl -x )
		if [ -n "$(DIget SmartctlOpts)" ]; then
			cmd+=( $(DIget SmartctlOpts) )		# no quotes!
		fi
		cmd+=( "$dev" )
		;;
	MAC)
		# first enable S.M.A.R.T. operations
		$VEXEC sudo maxwell -b -d "$dev"	

		# add a date line:
		$VEXEC printf "\nLocal Time is:    $(date)\n"

		cmd+=( maxwell -r -d "$dev" )
		;;
	esac

	# Do it
	$VEXEC "${cmd[@]}" | tr -d '\015\023'	# LF and ^S (added by maxwell)
}


#===============================================================================
# DRIVE OPERATIONS
# 	All DRIVE OPERATION functions should be called:
#		OP_<operation> 
#   and take a <drive> parameter which is the name of the subdirectory
#   of $DRIVE_INFO_DIR.
#   An OPERATION can have a "PRE" function called:
# 		OP_<operation>_PRE
# 	(no parameters) which is executed first before the loop over all drives.


#==========================================================
# OP_SMARTX
#======================================
function OP_SMARTX()
# Do a smartctl -x for <drive> on its host to stdout.
# If OUTMODE=WRITE, save it as a timestamped .smartx
{
	dlog "${FUNCNAME[0]}($*)"
	local drive="$1"; shift
	local fname opts
	SMARTX_FNAME=		# global

	case "$OUTMODE" in
	DIFF)
		fname="$(get_recent_smartx "$drive")"
		if [ -z "$fname" ]; then
			log "OP_SMARTX: $drive:  No .smartx files found for DIFF"
			return 1
		fi
		SMARTX_FNAME="$fname"	# save the fname
		opts=
		if [ $VERBOSE -lt 1 ]; then opts=-q ; fi
		if exec_SMARTX "$drive" | diff $opts "$fname" - ; then
			vlog "$fname: no differences"
		fi
		;;
	WRITE)
		# Generate a timestamped .smartx filename
		name="$(DIget Name)"
		name="$( printf "%s" "$name" | tr -cd '[._a-zA-Z0-9-]' )"
		fname="$drive/$name.$(date +%Y%m%d).smartx"
		if [ -e "$fname" ]; then
			if [ -z "$FORCE" ]; then
				log "$fname: already exists; use -f to overwrite"
				return 1
			else
				vlog "$fname: already exists and -f specified; overwriting"
			fi
		fi
		if [ -n "$DRYRUN" ]; then
			log "exec_SMARTX \"$drive\" > \"$fname\""
		else
			vlog "# exec_SMARTX \"$drive\" > \"$fname\""
			NEEDS_CLEANING=
			exec_SMARTX "$drive" > "$fname"
			if [ "$NEEDS_CLEANING" == true ]; then
				FILES_TO_CLEAN+=( "$fname" )
			fi
		fi
		SMARTX_FNAME="$fname"	# save the fname
		;;
	STDOUT)
		exec_SMARTX "$drive"
		;;
	esac
}



#==========================================================
# OP_REPORT
function OP_REPORT_PRE()
# Display the report header
{
	dlog "${FUNCNAME[0]}($*)"
	local var="REPORT_$REPORT[@]"
	local code getr key fwidth fmt sep first

	if [ -z "$REPORT" ]; then return 0; fi

	if [ -n "$DO_TSV" ]; then
		printf "# vim: nowrap:vts=4,30\n"
		sep=$'\t'
	else
		sep=' '
	fi
	printf "#"

	for code in "${!var}"; do
		code_explode "$code"
		if [ -n "$DO_TSV" ]; then fmt="%s"; fi
		printf "$sep$fmt" "$key"
	done
	printf "\n"
}

#======================================
function OP_REPORT()
# OP_REPORT <drive>
# Display the info <report> for <drive>
{
	dlog "${FUNCNAME[0]}($*)"
	local drive="$1"; shift
	local var="REPORT_$REPORT[@]"
	local code getr key fwidth fmt sep

	if [ -z "$REPORT" ]; then return 0; fi

	if is_function "REPORT_${REPORT}_MASSAGER"; then
		"REPORT_${REPORT}_MASSAGER" "$drive"
	fi

	if [ -n "$DO_TSV" ]; then
		sep=$'\t'
	else
		sep=' '
	fi

	# do the report
	printf " "
	for code in "${!var}"; do
		code_explode "$code"
		val="$($getr "$key")"
		if [ -n "$DO_TSV" ]; then
			fmt="%s"		# override
		else
			if [ -z "$val" ]; then val="-"; fi	# ensure it's non-white for sort
		fi
		printf "$sep$fmt" "$val"
	done
	printf "\n"
}

#======================================
function code_explode()
# code_explode <code>
# Explode a REPORT code <ARRAY>:<key>:<width> and set variables in the caller.
{
	local carr
	carr=( ${code//:/ } )		# bust code into an array
	getr="${carr[0]}get"		# array getter
	key="${carr[1]}"			# key
	fwidth="${carr[2]}"			# field width
	if [ -z "$fwidth" ]; then fwidth=6; fi	 # default
	if (( fwidth <= ${#key} )); then fwidth="$(( ${#key} + 1 ))"; fi
	fmt="%-${fwidth}s"
}




#==========================================================
# OP_INFO
function OP_INFO()
# OP_INFO <drive>
# Query the drive on its Host, return a merged INFO.txt,
# produce output according to OUTMODE (STDOUT/DIFF/WRITE).
{
	dlog "${FUNCNAME[0]}($*)"
	local drive="$1"; shift
	local host serial sysid dev tran model
	local ret fname
	local cmd=()

	host="$(DIget Hostname)"
	if is_remote "$host"; then
		# execute remote query and collect response into local vars
		cmd=( "$host" "$DRIVE_INFO_PATH" "${REM_OPTS[@]}" )
		cmd+=( -q -I "$drive" )		# quiet INFO query
		# match this with Terse TSV output below
		IFS=$'\t' read -r serial sysid dev tran model < <( rssh "${cmd[@]}" )

		# sanity check
		ret=$?
		if [ $ret -ne 0 ]; then
			vlog "$host:$drive: Remote -I command returned non-zero: $ret"
			logwarn "$host: No ACTIVE drive with sysid='$sysid'"
			return $ret
		fi
		[ "$serial" == "$drive" ] || err "Assertion failed: \$serial==\$drive"

		# Add entry to ACTIVE arrays (for update_INFO)
		if is_ACTIVE "$sysid" ; then
			# already exists
			logwarn "$host:$drive: ACTIVE entry for $sysid already exists" \
				"for host='$(get_ACTIVE $sysid Hostname)'"
			dump_ACTIVE
			return 1
		fi
		set_ACTIVE "$sysid" "$host" "$dev" "$tran" "$model"

	elif [ $? == 2 ]; then
		# remote, but disabled or not responding; fail
		return 1

	else
		# Not remote; get local info from ACTIVE array
		sysid="$(DIget SysID)"
		if is_ACTIVE "$sysid" ; then
			host="$( get_ACTIVE "$sysid" Hostname)"
			dev="$( get_ACTIVE "$sysid" Dev)"
			tran="$( get_ACTIVE "$sysid" Tran)"
			model="$( get_ACTIVE "$sysid" Model)"
		else
			logwarn "SysID='$sysid': No such ACTIVE drive"
			return 1
		fi
	fi

	if [ -n "$QUIET" ]; then
		# Terse TSV output for parsing
		printf "%s\t%s\t%s\t%s\t%s\n" "$drive" "$sysid" "$dev" "$tran" "$model"
		return 0
	fi

	# merge new info and generate
	update_INFO "$drive"

	fname="$drive/INFO.txt"
	case "$OUTMODE" in
	DIFF)
		if ! generate_INFO | diff -q "$fname" - ; then
			if [ $VERBOSE -gt 0 ]; then
				generate_INFO | diff "$fname" -
			fi
		else
			vlog "$fname: no differences"
		fi
		;;
	WRITE)
		if [ -n "$FORCE" ] || ! generate_INFO | diff -q "$fname" - >/dev/null 2>&1; then
			if [ -n "$DRYRUN" ]; then
				log "generate_INFO > \"$fname\""
			else
				vlog "# generate_INFO > \"$fname\""
				generate_INFO > "$fname"
			fi
		else
			vvlog "$fname: no write required"
		fi
		;;
	STDOUT)
		generate_INFO
		;;
	esac

}


#==========================================================
# OP_STATS
function OP_STATS()
# OP_STATS <drive>
# Generate a STATS.txt line from the current DRIVE_STATS data;
# produce output according to OUTMODE (STDOUT/DIFF/WRITE).
{
	dlog "${FUNCNAME[0]}($*)"
	local drive="$1"; shift
	local host serial sysid dev tran model
	local ret fname
	local cmd=()

	fname="$drive/STATS.txt"
	case "$OUTMODE" in
	DIFF)
		if ! generate_STATS_line | diff -q <(tail -1 "$fname") - ; then
			if [ $VERBOSE -gt 0 ]; then
				vlog "current differs from $fname:"
				generate_STATS_line | diff <(tail -1 "$fname") -
			fi
		else
			vlog "$fname: no differences"
		fi
		;;
	WRITE)
		if [ -n "$DO_STATS_HEADER" ]; then
			if [ -n "$DRYRUN" ]; then
				log "generate_STATS_header >> \"$fname\""
			else
				vlog "# generate_STATS_header >> \"$fname\""
				generate_STATS_header >> "$fname"
			fi
		fi
		if [ -n "$DRYRUN" ]; then
			log "generate_STATS_line >> \"$fname\""
		else
			vlog "# generate_STATS_line >> \"$fname\""
			generate_STATS_line >> "$fname"
		fi
		;;
	STDOUT)
		generate_STATS_header
		generate_STATS_line
		;;
	esac
}


#==========================================================
# OP_PARTITIONS
function OP_PARTITIONS()
# Generate PARTITIONS.txt for <drive> to stdout
{
	dlog "${FUNCNAME[0]}($*)"
	local drive="$1"; shift
	log "OP_PARTITIONS: unimplemented"
}


#==============================================================================
# USAGE
usage(){
echo >&2 "\
Usage: $PROG [OPTIONS] [<drive> ...]

By default, show drive info for <drive> ... (or all drives if none provided).
<drive> is a DRIVE_INFO subdirectory.

    DRIVE_INFO=$DRIVE_INFO_DIR

Where referred to here, a smartx is an output of smartctl -x.

General Options:
    -d        Debug enable
    -E        Environment: dump the data structures.
    -f        Force overwrite if a file or entry already exists.
    -n        Don't make any changes; instead show what would be done.
    -q        Quiet; (Internal): produce terse output for parsing.
    -v        Increase verbosity.

Other Options:
    -U <op>   Execute a UTILITY operation (see below).
    -r        Enable queries to remote hosts; use twice to pass the above
              General Options to remote operations.
    -h        Print usage help and exit.

Report Options - these produce a report of the drives:
    -R <rep>  Produce a <rep> report. (See Reports below for available reports)
    -Z        Wellness: report the health status of each drive.
    -A        ACTIVE drive report (attached to hosts).
    -C        \"Cupboard\" - STOWED drive report.
    -t        TSV output (for Reports): produce tab-separated-value output.

Generate Operations - these instead produce an output file for the drives:
    -I        Query <drive> on its host, generate a merged INFO.txt to stdout.
              Use -f to override existing INFO.txt fields with new live info.
    -P        Query <drive> on its host, generate PARTITIONS.txt to stdout.
    -S        Query <drive> on its host, add a line to STATS.txt.
    -x        Do a smartctl -x query for <drive> on its host to stdout.
              In WRITE mode, write to a datestamped .smartx file.
    -D        DIFF mode: diff vs existing files rather than generate to stdout.
    -W        WRITE mode: replace existing files rather than generate to stdout.
    -V        Add a full :vts header before each STATS.txt line.

Filter Options (more than one can apply)
    -A        Only process ACTIVE drives (attached to hosts).
    -C        Only process STOWED \"cupboard\" drives.
    -E        Only process drives with TOTErrs > 0.
    -H <host> Only process drives attached to <host>.
    -L        Local.  Same as -H \$HOSTNAME.
    -O <os>   Only process drives attached to a <os> host (os=LNX|WIN|MAC).

Stats Source Options; mutually exclusive:
    -X        Do a smartctl -x query for <drive>, saved to .smartx, STATS.txt.
    -K        Do a smartctl -x query for <drive>, discard the .smartx.
    -J        Read the most recent .smartx file.
    -Q        Read the most recent (last) line in STATS.txt (the default).

The -A, -C, -E, -X, -K, -J, -Q options also set the operation to be a report;
subsequent options (-I, -S, -P) can change this.

An empty report (-R '') will traverse all specified drives (driveloop) without any report output.

Specifying an empty drive parameter ('') will skip the driveloop.

<rep>: Reports:"

	usage_reports
echo >&2 "\

<op>: Utility Operations:"
	usage_utilities

}



#======================================
function usage_reports()
{
	local rep var
	local sedopts=(		# to indent the second and subsequent lines
		-e ':a' -e 'N' -e '$!ba' -e 's/\n/\n                /g'
	)
	for rep in $( set | grep '^REPORT_.*_DESC' | sed 's/REPORT_\(.*\)_DESC=.*/\1/' ); do
		printf "    %-10s  " "$rep"
		var="REPORT_${rep}_DESC"
		echo "${!var}" | sed "${sedopts[@]}"
	done
}

#======================================
function usage_utilities()
{
	local op var
	local sedopts=(		# to indent the second and subsequent lines
		-e ':a' -e 'N' -e '$!ba' -e 's/\n/\n                /g'
	)
	for op in $( set | grep '^UTIL_.*_DESC' | sed 's/UTIL_\(.*\)_DESC=.*/\1/' ); do
		printf "    %-10s  " "$op"
		var="UTIL_${op}_DESC"
		echo "${!var}" | sed "${sedopts[@]}"
	done
}

#==============================================================================
# MAIN

PROG="`basename $0`"
HOSTNAME="$(hostname -s)"
SAVED_ARGV=( "$0" "$@" )
VERBOSE=0
DEBUG=
FORCE=
QUIET=
DO_DUMP=
SORTOPTS=
OUTMODE=STDOUT				# default: to stdout
DO_TSV=						# don't do TSV

OP=REPORT					# default: generate a report
REPORT="STATUS"				# default report
STATUS_FILTER=				# default: no status filter
HOST_FILTER=				# default: no host filter
OS_FILTER=					# default: no OS filter
ERR_FILTER=					# default: no error filter
EXEC_REMOTE=				# default: do not execute remotely
PASS_REMOTE_FLAGS=			# default: do not pass flags to remote commands
STATS_MODE=LINE				# default: take last line from STATS.txt
FILES_TO_CLEAN=()			# files to be cleaned
DO_STATS_HEADER=			# default: don't add a header to STATS.txt


OPTIND=1
while getopts R:ZtIPSxDWVACEH:LO:JKQXEdfnqvU:r\?h arg; do
	case "$arg" in

	# REPORT/FILTER OPTIONS
	R)	OP=REPORT; REPORT="$OPTARG"; 									;;
	Z)	OP=REPORT; REPORT="HEALTH"										;;
	t)	DO_TSV=true ;;

	# GENERATE OPTIONS
	I)	OP=INFO ;		STATUS_FILTER="ACTIVE";	OP_OPT="$arg"; REPORT=	;;
	P)	OP=PARTITIONS ;	STATUS_FILTER="ACTIVE";	OP_OPT="$arg"; REPORT=	;;
	S)	OP=STATS ;		STATUS_FILTER="ACTIVE";	OP_OPT="$arg"; REPORT=	;;
	x)	OP=SMARTX ;		STATUS_FILTER="ACTIVE";	OP_OPT="$arg"; REPORT=
		STATS_MODE=NONE
		;;
	D)	OUTMODE=DIFF ;;
	W)	OUTMODE=WRITE ;;
	V)	DO_STATS_HEADER=true ;;

	# FILTER OPTIONS
	A)	STATUS_FILTER="ACTIVE"	; OP=REPORT; REPORT="ACTIVE" 			;;
	C)	STATUS_FILTER="STOWED"	; OP=REPORT; REPORT="STOWED" 			;;
	E)	ERR_FILTER=true			; OP=REPORT; REPORT="TOTERRS"			;;
	H)	STATUS_FILTER="ACTIVE"	; HOST_FILTER="$OPTARG"					;; 
	L)	STATUS_FILTER="ACTIVE"	; HOST_FILTER="$HOSTNAME"				;;
	O)	STATUS_FILTER="ACTIVE"	; OS_FILTER="$OPTARG"					;; 

	# STATS INPUT OPTIONS
	J)	STATS_MODE=FILE			; OP=REPORT; REPORT="STATUS"			;;
	K)	STATS_MODE=DISCARD		; OP=REPORT; REPORT="ACTIVE"			;;
	Q)	STATS_MODE=LINE			; OP=REPORT; REPORT="STATUS"			;;
	X)	STATS_MODE=SAVE			; OP=REPORT; REPORT="ACTIVE"			;;

	# GENERAL OPTIONS
	E)	DO_DUMP=true ;;
	d) 	DEBUG=true ;;
	f) 	FORCE=true ;;
	n) 	DRYRUN=true ;;
	q) 	QUIET=true ;;
	v) 	let VERBOSE+=1 ;;

	# OTHER OPTIONS
	U)	OP=UTIL ; UTILOP="$OPTARG"; REPORT=				;;
	r)	if [ -n "$EXEC_REMOTE" ]; then
			# -r given twice
			PASS_REMOTE_FLAGS=true
		else
			EXEC_REMOTE=true
		fi
		;;
	[?h]) usage; exit 2 ;;
	*) echo >&2 "invalid option: $arg"; usage; exit 2 ;;
	esac
done
# skip option arguments:
shift `expr $OPTIND - 1`

# log command-line used to invoke
dlog "[$HOSTNAME] ARGV: ${SAVED_ARGV[*]}"

# Load active drive info
DIinit
DSinit
load_ACTIVE
if [ -n "$DO_DUMP" ]; then
	logpf "ACTIVE[]:\n"
	dump_ACTIVE
fi

#======================================
# UTILITY OPERATIONS  - do here and exit
if [ "$OP" = "UTIL" ]; then
	if is_function "UTIL_$UTILOP"; then
		UTIL_$UTILOP "$@"
		exit $?
	else
		logerr "No such utility operation: $UTILOP"
		exit 1
	fi
fi


#======================================
# DRIVE OPERATIONS from here down
cd "$DRIVE_INFO_DIR"

# Fix up parms = list of drives 
if [ $# == 0 ]; then
	# no parm specified ; do all drives (directories)
	DRIVES=( $(ls -1d -- */ | sed 's|/$||') )
elif [ -z "$*" ]; then
	# empty parm specified; skip driveloop
	exit 0
else
	# parms specified; clean them up
	DRIVES=()
	for d in "$@"; do
		d="${d%%/}"		# remove any trailing slash
		DRIVES+=( "$d" )
	done
fi


# REPORT? set SORTOPTS
if [ -n "$REPORT" ]; then
	var="REPORT_${REPORT}_SORTKEYS"
	SORTOPTS=( -bf )
	if [ -n "$DO_TSV" ]; then
		vvlog "SORTKEY(before)='${!var}'"
		SORTOPTS+=( -t $'\t' )
		SORTOPTS+=( $( sortkeyincr ${!var} ) )
	else
		SORTOPTS+=( ${!var} )
	fi
	vvlog "SORTOPTS='${SORTOPTS[@]}'"
fi

# REMOTE? set REM_OPTS
REM_OPTS=()
if [ -n "$EXEC_REMOTE" ]; then
	if [ -n "$PASS_REMOTE_FLAGS" ]; then
		if [ -n "$DRYRUN" ]; then REM_OPTS+=( -n ); fi
		if [ -n "$FORCE" ]; then REM_OPTS+=( -f ); fi
		if [ -n "$DEBUG" ]; then REM_OPTS+=( -d ); fi
		if [ -n "$QUIET" ]; then REM_OPTS+=( -q ); fi
		if [ -n "$DO_DUMP" ]; then REM_OPTS+=( -E ); fi
		for (( i=VERBOSE; i>0; i-- )) ; do REM_OPTS+=( -v ); done
	fi
fi

# Do it
if [ -n "$OP" ]; then
	op_pre
	if [ -n "${SORTOPTS[*]}" ]; then
		op_driveloop | sort "${SORTOPTS[@]}"
	else
		op_driveloop
	fi
fi

# Anything to clean?
if (( ${#FILES_TO_CLEAN[@]} > 0 )); then
	log "New files need cleaning:"
	for (( i=0; i<${#FILES_TO_CLEAN[@]}; i++ )); do
		log "	${FILES_TO_CLEAN[$i]}"
	done
fi
