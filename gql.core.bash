#!/usr/bin/env bash

declare GQL_CORE="$(readlink -f "${BASH_SOURCE[0]}")" 
declare GQL_DIR="$(dirname "$GQL_SCRIPT")"
declare -n GQL=GQL_GLOBAL
declare -i GQL_LAST_ID=0
declare -A GQL_GLOBAL
GQL[gql:core]="$GQL_CORE"
GQL[gql:dir]="$(dirname "${GQL[gql:core]}")"

##############################################################################
##############################################################################

function gql:main
{
    set -eu
    #trap gql:traceback ERR
    
    local OPTIND OPTARG OPT
    local -n GQL="${!GQL}"
    local -A GQL_MAIN
    
    gql:merge-config GQL_MAIN GQL
    local -n GQL=GQL_MAIN
    
    local name value
    
    while getopts 'C:H:U:V:' OPT
    do
        case "$OPT" in
        C) gql:merge-config GQL_MAIN "$OPTARG";;
        H) GQL[host]="$OPTARG";;
        U) GQL[url]="$OPTARG";;
        m) op=mutation;;
        V) GQL[vars]+="${GQL[vars]+ }$OPTARG";;
        ?) exit 65;;
        esac 
    done
    
    : "${GQL[url]:=${GQL_URL:-}}"
    
    shift $(( OPTIND - 1 ))
    
    local op="${1:-}"; shift || gql:usage "Operation is required"
    if declare -F "gql:op:$op" >/dev/null
    then
        "gql:op:$op" "$@"
    else
        gql:fatal invalid-operation "$op"
    fi
}

##############################################################################
##############################################################################

function gql:use
{
    local modname="$1"; shift || gql:required modname 'module name to use'
    local -n modulr="GQL[module:$modname]"
    local fn="${1:-}"; shift
    
    if [ "$fn" = - ]
    then
        fn="${FUNCNAME[1]}"
    fi;
    
    if [ ! "$modulr" ]
    then
        local source="${GQL[module:$modname:source]}"
        declare -A "GQL_MODULE_$(( ++GQL[id:last] ))"
        local -n GQL_MODULE="GQL_MODULE_${GQL[id:last]}"
        GQL_MODULE[module:name]="$modname"
        GQL_MODULE[module:source]="$source"
        
        {
            local GQL_LOG_CONTEXT="${GQL_LOG_CONTEXT:-$(caller 1)}"
            [ -r "$source" ] \
                || gql:fatal module-not-found "$modname" \
            && source "${source}" \
                || gql:fatal module-load-fail "$modname" \
            && gql:trace \
                "Loaded module '$modname' from $source (seeking '${fn}')"
        }            
    fi &&
    
    if [ "$fn" ]
    then
        if [ "${_GQL_USE_FN:-}" = "$fn" ]
        then
            gql:fatal use-export-failed "$modname" "$fn"
        else
            local _GQL_USE_FN="$fn"
            "$fn" "$@"; return $?
        fi
    fi
}

##############################################################################
##############################################################################

GQL[module:gql.query:source]="./gql.query.bash"
function gql:op:query                   { gql:use gql.query - "$@"; }
function gql:op:mutation                { gql:use gql.query - "$@"; }
function gql:op:do                      { gql:use gql.query - "$@"; }
function gql:op:spool                   { gql:use gql.query - "$@"; }

##############################################################################
##############################################################################

GQL[module:gql.builder:source]="./gql.builder.bash"
function gql:build-document             { gql:use gql.builder - "$@"; }
function gql:op:print                   { gql:use gql.builder - "$@"; }

##############################################################################
##############################################################################

GQL[module:gql.curl:source]="./gql.curl.bash"
function gql:agent:curl                 { gql:use gql.curl - "$@"; }

##############################################################################
##############################################################################

GQL[module:gql.format:source]="./gql.format.bash"
function gql:format-document            { gql:use gql.format - "$@"; }

##############################################################################
##############################################################################

GQL[module:gql.log:source]="./gql.log.bash"
function gql:log                        { gql:use gql.log - "$@"; }
function gql:dump                       { gql:use gql.log - "$@"; }
function gql:alert                      { gql:use gql.log - "$@"; }
function gql:fatal                      { gql:use gql.log - "$@"; }
function gql:error                      { gql:use gql.log - "$@"; }
function gql:warn                       { gql:use gql.log - "$@"; }
function gql:info                       { gql:use gql.log - "$@"; }
function gql:verbose                    { gql:use gql.log - "$@"; }
function gql:debug                      { gql:use gql.log - "$@"; }
function gql:trace                      { gql:use gql.log - "$@"; }
function gql:traceback                  { gql:use gql.log - "$@"; }

##############################################################################
##############################################################################

GQL[module:gql.help:source]="./gql.help.bash"
function gql:op:modules                 { gql:use gql.help - "$@"; }
function gql:op:help                    { gql:use gql.help - "$@"; }
function gql:usage                      { gql:use gql.help - "$@"; }

##############################################################################
##############################################################################

GQL[module:gql.config:source]="./gql.config.bash"
function gql:merge-config              { gql:use gql.config - "$@"; }

##############################################################################
##############################################################################
