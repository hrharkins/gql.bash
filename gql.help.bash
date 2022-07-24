
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

function gql:op:operations
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
    local front="${COMP_LINE:0:$COMP_POINT}"
    local -a words=( $front )
    local search="${words[-1]}"
    local prefix="${search%.*}"
    if [ "${front%$search}" = "$front" ]
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
    
    {
        gql:do '
            {
                __schema
                {
                    types
                    {
                        name
                        fields { name }
                    }
                }
            }
        ' | jq -r '
            (
                .__schema.types[]
                | (
                    [ .name ],
                    ( ( .fields // [] )[] | [ .name ] )
                )
            ) | @tsv
        ' ;
        gql:op:operations
    } |
    while read name
    do
        if [ ! "$search" -o "${name#$search}" != "$name" ]
        then
            echo "$prefix$name"
        fi
    done
}

##############################################################################
##############################################################################
