
GQL[log:level:TRACE]=-3
GQL[log:level:DEBUG]=-2
GQL[log:level:VERBOSE]=-1
GQL[log:level:INFO]=0
GQL[log:level:WARNING]=1
GQL[log:level:ERROR]=2
GQL[log:level:ALWAYS]=9999

GQL[log:level]="${GQL[log:level:${GQL_LOG_LEVEL:-}]:-${GQL_LOG_LEVEL:-0}}"
    
GQL[log:msg:argument-required]='Argument "%s" is required'
GQL[log:msg:argument-required:exit]=63
GQL[log:msg:module-not-found]='Module "%s" not found'
GQL[log:msg:module-load-fail]='Module "%s" failed to load'

GQL[exit:general]=1

##############################################################################
##############################################################################

function gql:log
{
    local -i level="${GQL[log:level:${1^^}]:-$1}"; 
        shift || gql:required log-level
    [ "$level" -lt "${GQL[log:level]}" ] && return 0
    local msg="$1"; shift || gql:required log-message
    
    local resolved="${GQL[log:msg:$msg]:-}"
    if [ "$resolved" ]
    then
        msg="$resolved"
    elif [ $# -gt 0 ]
    then
        msg+=" $@"
    fi        
    
    if [ "${GQL_LOG_CONTEXT:-}" ]
    then
        local -a ctx=( ${GQL_LOG_CONTEXT} )
        local file="${ctx[2]:-(unknown)}"
        local line="${ctx[0]:-(unknown)}"
        local fn="${ctx[1]:-(unknown)}"
        
        if [ "$msg" = '-' ]
        then
            echo "${GQL_LOG_PFEFIX:-}[In $fn at $file:$line]:"
            local GQL_LOG_PREFIX+="${GQL_LOG_INDENT:-  }"
            while read line
            do
                echo "$GQL_LOG_PREFIX$line"
            done
        else
            msg+=" [in $fn at $file:$line]"
            printf -- "${GQL_LOG_PFEFIX:-}$msg\n" "$@" >&2
        fi
    else
        if [ "$msg" = '-' ]
        then
            while read line
            do
                echo "$GQL_LOG_PREFIX$line"
            done
        else
            printf -- "${GQL_LOG_PFEFIX:-}$msg\n" "$@" >&2
        fi            
    fi
}

function gql:log-level
{
    local -i level="${GQL[log:level:${1^^}]:-$1}"; shift \
        || gql:required log-level
    GQL[log:level]="$level"
}

##############################################################################

function gql:trace
{
    local GQL_LOG_CONTEXT="${GQL_LOG_CONTEXT:-$(caller 1)}"
    gql:log TRACE "$@"
}

function gql:debug
{
    local GQL_LOG_CONTEXT="${GQL_LOG_CONTEXT:-$(caller 1)}"
    gql:log DEBUG "$@"
}

function gql:error      { gql:log ERROR "$@"; }
function gql:warning    { gql:log WARNING "$@"; }
function gql:info       { gql:log INFO "$@"; }
function gql:verbose    { gql:log VERBOSE "$@"; }

function gql:fatal
{
    local GQL_LOG_CONTEXT="${GQL_LOG_CONTEXT:-$(caller 1)}"
    local message="$1"; shift || gql:required 'fatal message'
    gql:log ALWAYS "$message" "$@"
    exit "${GQL[log:"$message":exit]:-${GQL[exit:general]}}"
}

##############################################################################

function gql:internal-error
{
    local GQL_LOG_CONTEXT="$(caller 1)"
    gql:fatal "$@" 
}

function gql:required
{
    gql:internal-error argument-required "$1"
}

##############################################################################

function gql:alert              
{ 
    local GQL_LOG_CONTEXT="$(caller 0)"
    gql:log ALWAYS "$@"; 
}

function gql:dump
{
    local GQL_LOG_CONTEXT="$(caller 0)"
    declare -p "$@" | gql:log ALWAYS -
}

##############################################################################

function gql:traceback
{
    local -i depth=0
    echo here
}
