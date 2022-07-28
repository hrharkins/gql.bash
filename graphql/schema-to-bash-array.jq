def get_type_name:
    . as $type |
    if ( $type.kind == "LIST" )
    then
        $type.ofType | get_type_name
    else
        $type.name // $type.kind
    end
;

def load_schema:
    . as $schema |
    (
        {
            "query": $schema.queryType,
            "mutations": $schema.mutationType,
            "subscription": $schema.subscriptionType
        }  | to_entries | map( select(.value != null) ) | 
        (
            [ "", ( map( .key ) | join( " " ) ) ]
            
            , (map(
                .key as $key | .value as $value |
                [ ("/" + $key), $value.name ]
            ) | .[])
        )
        
        , ( $schema.types | map(
            . as $type | 
            (
                [ 
                    $type.name, 
                    (
                        (
                            ( ( $type.fields // [] ) | map( .name ) )
                        ) | join(" ")
                    )                        
                ]
                
                , ( ( $type.fields // [] ) | map(
                    . as $field |
                    ( $field.type | get_type_name ) as $typename |
                    [ $type.name + "/" + $field.name, $typename ]
                ) | .[])
            )
         ) | .[])
        
        , empty
    )
;

( .__schema | load_schema ) | @tsv
