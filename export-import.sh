#!/bin/bash
DELETE_FILES="NO";
while getopts ":d" opt; do
  case $opt in
    d) DELETE_FILES="YES"
    ;;
  esac
done

URL_SOURCE="https://yougit.com.br";
URL_TARGET="http://targetgit.com.br";
TOKEN_SOURCE="yourTOKEN";
TOKEN_TARGET="targeTOKEN";
STATUS_OK="finished";
PROJECT_NOT_FOUND="404 Project Not Found";

[ -f retorno.json ]; rm -rf retorno.json;
echo "Buscando projetos na Origem."
curl -XGET  -k -s --header "PRIVATE-TOKEN: $TOKEN_SOURCE" --form "archived=false" "$URL_SOURCE?pagination=keyset&per_page=1000&order_by=id&sort=asc" | jq '.[] | .id' | tail -n +2 > retorno.json;

[ -f retorno_target.json ]; rm -rf retorno_target.json;
echo "Buscando projetos no Destino."
curl -XGET -s --header "PRIVATE-TOKEN: $TOKEN_TARGET" --form "archived=false" "$URL_TARGET/projects?pagination=keyset&per_page=1000&order_by=id&sort=asc" | jq '.[] | .path_with_namespace' | tail -n +2 > retorno_target.json;

if [ $DELETE_FILES == "YES" ]; then
    for PROJECT_ID in `cat retorno.json`; do
        PROJECT_JSON=`curl -XGET -k -s --header "PRIVATE-TOKEN: $TOKEN_SOURCE" "$URL_SOURCE/$PROJECT_ID"`;
        PROJECT_NAME=`echo $PROJECT_JSON  | jq -r '.name'`;
        PROJECT_PATH=`echo $PROJECT_JSON  | jq -r '.path_with_namespace' | sed "s/\/$PROJECT_NAME//g"`;

        echo "Verificando se já existe no destino o projeto [$PROJECT_ID-$PROJECT_NAME]";
        for PROJECT_TARGET_ID in `curl -XGET -k -s --header "PRIVATE-TOKEN: $TOKEN_TARGET"  "$URL_TARGET/search?scope=projects&search=$PROJECT_NAME" | jq -r ".[] | .id"`; do
            echo "Excluindo no destino o projeto [$PROJECT_TARGET_ID-$PROJECT_NAME]";
            curl -XDELETE -s --header "PRIVATE-TOKEN: $TOKEN_TARGET"  "$URL_TARGET/projects/$PROJECT_TARGET_ID" > /dev/null;
            while true; do
                RETURN_MESSAGE=$(curl -XGET -k -s --header "PRIVATE-TOKEN: $TOKEN_TARGET"  "$URL_TARGET/projects/$PROJECT_TARGET_ID" | jq -r ".message");
                if [[ ! -z $RETURN_MESSAGE ]]; then
                    if [[ $RETURN_MESSAGE == $PROJECT_NOT_FOUND ]]; then
                        break;
                    fi
                fi 
                echo -n "*"
                sleep 0.5;
            done            
        done
    done

    echo "";
    echo "Aguardando exclusões serem confirmadas....";
    sleep 5s;
    echo "";
fi

for PROJECT_ID in `cat retorno.json`; do
    PROJECT_JSON=`curl -XGET -k -s --header "PRIVATE-TOKEN: $TOKEN_SOURCE" "$URL_SOURCE/$PROJECT_ID"`;
    PROJECT_NAME=`echo $PROJECT_JSON  | jq -r '.name'`;
    PROJECT_PATH=`echo $PROJECT_JSON  | jq -r '.path_with_namespace' | sed "s/\/$PROJECT_NAME//g"`;

    if [ $DELETE_FILES == "NO" ]; then
        echo ""
        echo  "Pesquisando ${PROJECT_PATH}/${PROJECT_NAME}";
        if [ `grep "$PROJECT_PATH/$PROJECT_NAME" retorno_target.json | wc -l` -gt 0 ]; then
            echo -n " já importado anteriormente.";
            continue;
        fi
    fi
    echo "";    

    echo "Exportando projeto [$PROJECT_ID-$PROJECT_NAME]";
    curl -XPOST -s -k --header "PRIVATE-TOKEN: $TOKEN_SOURCE" "$URL_SOURCE/$PROJECT_ID/export/" > /dev/null;
    while [ `curl -XGET -s --header "PRIVATE-TOKEN: $TOKEN_SOURCE" "$URL_SOURCE/$PROJECT_ID/export/" | grep $STATUS_OK | wc -l` -lt 1 ]; do
        echo -n "*"
        sleep 0.5;
    done
    echo "";

    echo "Efetuando download do projeto [$PROJECT_ID-$PROJECT_NAME]";
    curl -s --header "PRIVATE-TOKEN: $TOKEN_SOURCE" --remote-header-name --remote-name "$URL_SOURCE/$PROJECT_ID/export/download";
    FILENAME=$(ls `date +"%Y-%m-%d"`*);

    if [ -f $FILENAME ]; then
        echo "Importando projeto [$PROJECT_ID-$PROJECT_NAME]"
        PROJECT_JSON=`curl -XPOST -s --header "PRIVATE-TOKEN: $TOKEN_TARGET" --form "namespace=$PROJECT_PATH" --form "name=$PROJECT_NAME" --form "path=$PROJECT_NAME" --form "file=@$FILENAME" "$URL_TARGET/projects/import"`;
        PROJECT_TARGET_ID=`echo $PROJECT_JSON | jq -r '.id'`;

        if [ $PROJECT_TARGET_ID == "null" ]; then
            if [ `echo $PROJECT_JSON | grep 'error' | wc -l` -gt 0 ]; then
                echo "Erro no processo de importação $(echo $PROJECT_JSON | jq -r '.error')";
            elif [ `echo $PROJECT_JSON | grep 'message' | wc -l` -gt 0 ]; then
                echo "Erro no processo de importação $(echo $PROJECT_JSON | jq -r '.message')";
            fi
        else 
            while [ $(curl -XGET -s --header "PRIVATE-TOKEN: $TOKEN_TARGET"  "$URL_TARGET/projects/$PROJECT_TARGET_ID/import" | jq -r ".import_status") != $STATUS_OK ]; do
                echo -n "*"
                sleep 0.5;
            done
            echo "";        
        fi

        echo "Apagando arquivo $FILENAME"
        rm -rf $FILENAME;
    fi

    sleep 5s;
done
