
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
                    fields { name }
                }
            }
        }
    ' | jq -r '
        .__schema as $schema |
        
        $schema.types[] | map( { (.name): . } ) as $types |
        
        ( $types | debug) |
        
        def type_paths($what):
            $what[0] as $path |
            $what[1] as $type |
            if(($type == null) or ($types[$type] == null))
            then
                empty
            else
                ($types[$type].fields // [])[] | 
                    (type_paths([$path + "." + .name, .type]))
            end
        ;
            
        (
            [ "query" ],
            [ "mutation" ],
            [ "subscription" ],
            type_paths(["query", $schema.queryType])
            
        ) | @tsv
        
    '
}
