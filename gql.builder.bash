
##############################################################################
##############################################################################

function gql:build-document
{
    local -n _doc="$1"; shift \
        || gql:requiree doc 'Destination document variable'
    _doc[op]="$1"; shift || gql.required operation "GraphQL operation"
    
    local OPTIND OPTARG OPT
    while getopts 'n:' OPT
    do
        case "$OPT" in
        n) _doc[name]="$OPTARG";;
        esac
    done
    shift $(( OPTIND - 1 ))

    local -a args=( "$@" )
    local -i argidx=0 nargs="${#args[@]}"
    
    gql:build-params "${!_doc}" doc:vars
    gql:build-directives "${!_doc}" doc:directives
}

##############################################################################
##############################################################################

function gql:build-params
{
    local -n _doc="$1"; shift \
        || gql:requiree doc 'Destination document variable'
    local path="$1"; shift || gql:required path 'path for params'
    local -i count=0

    local arg name value
    while [ $argidx -lt $nargs ]
    do
        arg="${args[$argidx]}"
        
        value="${arg#*=}"
        if [ "$value" = "$arg" ]
        then
            value="${arg#*:}"
            if [ ! "$value" -o "$value" = "$arg" ]
            then
                break
            else
                name="${arg%%:*}"
            fi                
        else
            name="${arg%%=*}"
            value="\"$value\""
        fi
        
        _doc["$path"/$name]="$value"
        _doc["$path"/"$count":name]="$name"
        _doc["$path"/"$count":value]="$name"
        (( ++count ))
        (( ++argidx ));
    done;
    
    if [ $count -gt 0 ]
    then
        _doc["$path"]="$count"
    fi
}

##############################################################################
##############################################################################

function gql:build-directives
{
    local -n _doc="$1"; shift \
        || gql:requiree doc 'Destination document variable'
    local path="$1"; shift || gql:required path 'path for params'
    local -i count=0

    local arg    
    while [ $argidx -lt $nargs ]
    do
        arg="${args[$argidx]}"
        local directive="${arg#@}"
        if [ "$directive" = "$arg" ]
        then
            break
        else
            (( ++argidx ))
            _doc["$path/$count"]="$directive"
            gql:build-params "${!_doc}" "$path/$count:args"
            (( ++count ))
        fi
    done        
    
    if [ $count -gt 0 ]
    then
        _doc["$path"]="$count"
    fi
}