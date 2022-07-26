
##############################################################################
##############################################################################

function gql:op:types
{
    gql:type-list
}

##############################################################################
##############################################################################

function gql:type-list
{
    gql:do '
        query
        {
            __schema
            {
                types { name }
            }
        }
    ' | jq -r '( .__schema.types[] | [ .name ] ) | @tsv'
}

##############################################################################
##############################################################################

function gql:name-list
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
    ' 
}

##############################################################################
##############################################################################

function gql:paths
{
    gql:do '
        {
            __schema
            {
                queryType { name }
                mutationType { name }
                subscriptionType { name }
                types
                {
                    name
                    fields { name type { kind name } }
                }
            }
        }
    ' | jq -r '
        .__schema as $schema |
        
        $schema.types | map( { (.name): . } ) | add as $types |
        
        def type_paths($what):
            $what[0] as $path |
            $what[1] as $typeref |
            
            if ( $typeref == null )
            then
                empty
            else
                [ $path ],
                $types[$typeref.name // ""] as $type |
                (
                    if ( $type == null )
                    then
                        empty
                    else
                        ($type.fields // [])[] |
                        (
                            type_paths([
                                $path + "." + .name,
                                .type
                            ])
                        )
                    end
                )
            end
        ;
            
        (
            type_paths(["query", $schema.queryType]),
            type_paths(["mutations", $schema.mutationType]),
            type_paths(["subscriptions", $schema.subscriptionType])
        ) | @tsv
        
    '
}

##############################################################################
##############################################################################

function gql:types
{
    local -n dest="$1"; shift || gql:required 'Destination variable'

    while read type field subtype
    do
        subtype="${subtype#[}"
        subtype="${subtype#!}"
        subtype="${subtype%]}"
        dest["$type:$field"]="$subtype"
    done < <(
        gql:do '
            {
                __schema
                {
                    queryType { name }
                    mutationType { name }
                    subscriptionType { name }
                    types
                    {
                        name
                        fields { name type { kind name } }
                    }
                }
            }
        ' | jq -r '
            .__schema | . as $schema |
            (
                if ( .queryType == null )
                then
                    empty
                else
                    [ "/", "query", .queryType.name ]
                end,
                
                if ( .mutationType == null )
                then
                    empty
                else
                    [ "/", "mutation", .mutationType.name ]
                end,
                
                if ( .subscriptionType == null )
                then
                    empty
                else
                    [ "/", "subscription", .subscriptionType.name ]
                end,
                
                ( .types[] |
                (
                    . as $type |
                    (
                        ($type.fields // [])[] |
                        (
                            . as $field |
                            [ $type.name, $field.name, 
                                $field.type.name // $field.type.kind ]
                        )
                    )
                ) )
                
            ) | @tsv
        '
    )        
}