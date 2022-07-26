
##############################################################################
##############################################################################

function gql:op:print
{
    local op="$1"; shift || gql:required op 'GQL operation'
    local -A _gql_doc
    gql:build-document _gql_doc "$op" "$@"
    gql:format-document _gql_doc
}

##############################################################################
##############################################################################

function gql:build-document
{
    local -n _doc="$1"; shift \
        || gql:requiree doc 'Destination document variable'
    local op="$1"; shift || gql.required operation "GraphQL operation"
    local name='' _lastpath lastpath_var
    
    local OPTIND OPTARG OPT
    local print= dump=
    while getopts 'n:pdL:' OPT
    do
        case "$OPT" in
        n) name="$OPTARG";;
        p) print=1;;
        d) dump=1;;
        L) lastpath_var="$OPTARG";;
        esac
    done
    shift $(( OPTIND - 1 ))

    local -a args=( "$@" )
    local -i argidx=0 nargs="${#args[@]}"
    
    _doc[:op]="$op"
    _doc[:name]="$name"
    _gql_build_params "${!_doc}" :vars
    _gql_build_directives "${!_doc}" :directives
    _gql_build_selectors "${!_doc}" ''
    
    if [ "$dump" ]
    then
        gql:dump "${!_doc}"
    fi
    
    if [ "$print" ]
    then
        gql:format-document "${!_doc}"
    fi
    
    if [ "${lastpath_var:-}" ]
    then
        local -n lastpath_ref="$lastpath_var"
        lastpath_ref="$op$_lastpath"
    fi
}

##############################################################################
##############################################################################

function _gql_build_params
{
    local -n _doc="$1"; shift \
        || gql:requiree doc 'Destination document variable'
    local path="$1"; shift || gql:required path 'path for params'
    local -n params="_doc[$path]"

    local arg name value
    while [ $argidx -lt $nargs ]
    do
        arg="${args[$argidx]}"
        
        if [ "${arg#@}" != "$arg" ]
        then
            break
        fi
        
        name="${arg%%:*}"
        if [ "$name" != "$arg" -a "${name#*=}" = "$name" ]
        then
            value="${arg#*:}"
            if [ ! "$value" ]
            then
                break
            elif [ "${value#=}" != "$value" ]
            then
                value="\$${value#=}"
            fi
        else
            value="${arg#*=}"
            if [ "$value" = "$arg" ]
            then
                break
            else
                name="${arg%%=*}"
                value="\"$value\""
            fi
        fi            
        
        params+="${params+ }$name"
        _doc["$path":"$name"]="$value"
        (( ++argidx ));
    done;
}

##############################################################################
##############################################################################

function _gql_build_directives
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
            _gql_build_params "${!_doc}" "$path/$count:args"
            (( ++count ))
        fi
    done        
    
    if [ $count -gt 0 ]
    then
        _doc["$path"]="$count"
    fi
}

##############################################################################
##############################################################################

function _gql_build_selectors
{
    local -n _doc="$1"; shift \
        || gql:requiree doc 'Destination document variable'
    local path="$1"; shift || gql:required path 'path for selectors'
    local target="$path"
    local -n selectors='_doc[$target:selectors]'
    local prefix
    _lastpath="$path"
    
    local arg
    while [ $argidx -lt $nargs ]
    do
        arg="${args[$argidx]}"
        case "$arg" in
        '[')
            _doc["$target:output"]='table'
            ;&
            
        '{')
            (( ++argidx ))
            _gql_build_selectors "${!_doc}" "$target"
            ;;
            
        '}' | ']')
            (( ++argidx ))
            break
            ;;
            
        *)
            _lastpath="$path.$arg"
            (( ++argidx ))
            prefix="${arg%%.*}"
            if [ "$prefix" ]
            then
                # Non-empty prefix means single term or leading name.  The
                # target is continued for .a.b...
                target="$path"
            fi
            
            while [ "$prefix" != "$arg" ]
            do
                arg="${arg#*.}"
                if [ "$prefix" ]
                then
                    if [ ! "${_doc[$target.$prefix:name]:+_}" ]
                    then
                        selectors+="${selectors+ }$prefix"
                    fi                    
                    
                    target+=".$prefix"
                    : "${_doc["$target:name"]:="$prefix"}"
                fi
                
                prefix="${arg%%.*}"
            done
            
            if [ ! "${_doc[$target.$arg:name]:+_}" ]
            then
                selectors+="${selectors:+ }$arg"
            fi                
            target+=".$arg"
            _doc["$target:name"]="$arg"
            _gql_build_params "${!_doc}" "$target:args"
            _gql_build_directives "${!_doc}" "$target:directives"
            
            case "${args[$argidx]:-}" in
            '[')
                _doc["$target:output"]='table'
                ;&
            
            '{')
                (( ++argidx ))
                _gql_build_selectors "${!_doc}" "$target"
                target="$path"
            esac
            ;;
        esac
    done
}
