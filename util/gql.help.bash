
##############################################################################
##############################################################################

function gql:op:modules
{
    declare -p "${!GQL}"
}

##############################################################################
##############################################################################

function gql:usage
{
    echo "USAGE: $@"
    exit 65
}

##############################################################################
##############################################################################

function gql:help:operations
{
    declare -F |
    while read _d _a fn
    do
        local op="${fn#gql:op:}"
        if [ "$op" != "$fn" ]
        then
            echo "$op"
        fi
    done
}

##############################################################################
##############################################################################

function gql:op:complete
{
    local COMPTERM="$(printf '\b')"
    local front="${COMP_LINE:0:$COMP_POINT}$COMPTERM"
    local -a words=( $front )
    local search="${words[-1]}"
    words=( "${words[@]:1}" )
    search="${search%"$COMPTERM"}"
    local prefix="${search%.*}"
    if [ "${front%$search$COMPTERM}" = "$front" ]
    then
        search=
        prefix=
    else
        search="${search##*.}"
        if [ "$prefix" = "$search" ]
        then
            prefix=
        else
            prefix+=.
        fi
    fi        
    
#    
#    {
#        gql:name-list
#        gql:op:operations
#    } |
    gql:complete:main "${words[@]}" | 
    while read name
    do
        if [ ! "$search" -o "${name#$search}" != "$name" ]
        then
            echo "$prefix$name"
        fi
    done
}

##############################################################################

function gql:complete:main
{
    local OPTIND OPTARG OPT
    while getopts 'C:H:U:V:P:' OPT
    do
        case "$OPT" in
        P) GQL[profile]="$OPTARG";;
        esac
    done
    shift $(( OPTIND - 1 ))

    case $# in
    0)
        return;;
    
    1)
        gql:help:operations 
        ;;
        
    *)        
        local fn="gql:complete:op:$1"
        if declare -F "$fn" >/dev/null
        then
            "$fn" "$@"
        fi
        ;;
    esac
}

##############################################################################
##############################################################################

function gql:complete:op:query
{
    local -A doc types
    gql:types types
    local lastpath subpath
    gql:build-document doc query -L lastpath "$@"
    
    local type=/
    local -a pathparts=( ${lastpath//./ } )
    unset pathparts[-1]
    for subpath in "${pathparts[@]}"
    do
        type="${types[$type:$subpath]:-}"
        if [ ! "$type" ]
        then
            return
        fi
    done
    
    local key
    for key in "${!types[@]}"
    do
        if [ "${key#$type:}" != "$key" ]
        then
            echo "${key#$type:}"
        fi
    done
    
    echo '{'
}
