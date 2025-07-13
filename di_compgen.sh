#!/bin/bash

# This is sourced by ~/.aliases

# TEST with:
# 

#==============================================================================
# DRIVE_INFO command auto-completion
# Auto-complete by Name: property found in the drive's INFO.txt file,
# replacing it with the drive directory (serialno) when found.
DRIVE_INFO_DIR=/House/INSTALL/Common/DRIVE_INFO
function _driveinfo_compgen()
{
	local cmd="$1"; shift
	local pat="$1"; shift
	local f d val
	local i count match
	local DIRS=()
	local NAMES=()
	local EXACT=()

	if [[ "$pat" =~ / ]]; then
		# it's a path; use normal file autocomplete:
		if [[ "$pat" =~ ^/ ]]; then
			# absolute path
			COMPREPLY=( $( compgen -f -- "$pat" ) )
		elif [ "$PWD" == "$DRIVE_INFO_DIR" ]; then
			# relative path and we're in DRIVE_INFO
			COMPREPLY=( $( compgen -f -- "$pat" ) )
		else
			# change to full path...
			COMPREPLY=( $( compgen -f -- "$DRIVE_INFO_DIR/$pat" ) )
		fi
		return $?
	fi
	# not a dir or file; search for Drive Name in INFO.txt
	while read f val; do
		d="${f%%/INFO.txt:Name:}"		# combined filename + matched col1
		d="${d##*/}"					# last path part == drive serialno
		DIRS+=( "$d" )
		NAMES+=( "$val" )
	done < <( grep -E "^Name:	$pat"  "$DRIVE_INFO_DIR"/*/INFO.txt )

	case ${#NAMES[@]} in
	0)	COMPREPLY=()					;;
	1)	COMPREPLY=( "${DIRS[0]}" )		;;		# found
	*)	# multiple matches; check if any are exact
		EXACT=()
		for (( i=0; i<${#NAMES[@]}; i++ )); do
			if [ "${NAMES[i]}" == "$pat" ]; then
				EXACT+=( "${DIRS[i]}" )
			fi
		done
		case ${#EXACT[@]} in
		0)	COMPREPLY=( "${NAMES[@]}" )		;;		# continue auto-complete
		1)	# one exact match
			# XXX: what to do with the other longer possible matches? 
			# They will never get auto-completed...
			# terminate with a '/'?  Ugh..  
			# nevermind; deal with it if/when it ever happens...
			COMPREPLY=( "${EXACT[0]}" )		
			;;
		*)	# multiple exact matches; error basically; one needs to be renamed
			printf >&2 "\nWARNING: Multiple drives named '$pat': ${EXACT[*]}\n"
			COMPREPLY=( "${EXACT[0]}" )			# return the first one
			;;
		esac
	esac
}

alias driveinfo="$DRIVE_INFO_DIR/driveinfo.sh"
complete -o nospace -F _driveinfo_compgen driveinfo

alias divi='vim -X'
complete -o nospace -o filenames -F _driveinfo_compgen divi
