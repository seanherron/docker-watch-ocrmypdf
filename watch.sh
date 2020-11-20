#!/bin/bash

. /appenv/bin/activate

WOCR_CONSUME_PATH=${WOCR_CONSUME_PATH:-/consume}

inotifywait -r -m $WOCR_CONSUME_PATH -e create -e moved_to |
    while read path action file; do
        subdirectory=""

        if [[ $path =~ ^$WOCR_CONSUME_PATH/(.*?)/$ ]]; then
            subdirectory=${BASH_REMATCH[1]}
        fi

        fullfile=$path$file
        extension="${file##*.}"
        filename="${file%.*}"
        tmpname=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 6 | head -n 1)

        echo "$file was created. subdir=$subdirectory extension=$extension filename=$filename tmpname=$tmpname"

        filesize=$(stat -c%s $fullfile)
        echo "sleeping 2s"
        sleep 2

        while [[ $filesize -lt $(stat -c%s "$fullfile") ]]; do
            filesize=$(stat -c%s "$fullfile")
            echo "waiting for transfer to finish (size=$filesize)"
            sleep 2
        done

        if [[ ! "$extension" =~ ^(pdf|jpg|jpeg|png|PDF|JPG|JPEG|PNG)$ ]]; then
            echo $extension is not supported. Skipping.
            continue
        fi

        if [ $extension != 'pdf' ]; then
            echo $file is an image. running img2pdf
            img2pdf $fullfile -o /tmp/$tmpname.pdf
            rm $fullfile

            fullfile=/tmp/$tmpname.pdf
            extension=pdf
        fi

        # run ocr command
        cmdVarName="WOCR_CMD"
        if [ ! -z "$subdirectory" ]; then
            cmdVarName="WOCR_CMD_$subdirectory"
            if [ -z "${!cmdVarName}" ]; then
                echo $cmdVarName is not set. Exiting.
                continue
            fi
        fi

        ocr_cmd=$(echo ${!cmdVarName} | sed "s|%INFILE%|$fullfile|" | sed "s|%OUTFILE%|/tmp/$filename.pdf|")
        fullfile=/tmp/$filename.pdf

        # run ocr command
        echo $ocr_cmd
        $ocr_cmd

        cmdVarName="WOCR_AFTERCMD"
        if [ ! -z "$subdirectory" ]; then
            cmdVarName="WOCR_AFTERCMD_$subdirectory"
            if [ -z ${!cmdVarName} ]; then
                echo $cmdVarName is not set. Using default.
                cmdVarName="WOCR_AFTERCMD"
            fi
        fi

        if [ ! -z "${!cmdVarName}" ]; then
            after_cmd=$(echo ${!cmdVarName} | sed "s|%FILE%|$fullfile|")

            echo $after_cmd
            $after_cmd
        else
            echo no WOCR_AFTER command set.
        fi

        cmdVarName="WOCR_AFTERCOPYCMD"
        if [ ! -z "$subdirectory" ]; then
            cmdVarName="WOCR_AFTERCOPYCMD_$subdirectory"
            if [ -z ${!cmdVarName} ]; then
                echo $cmdVarName is not set. Using default.
                cmdVarName="WOCR_AFTERCOPYCMD"
            fi
        fi

        if [ ! -z "${!cmdVarName}" ]; then
            aftercopy_cmd=$(echo ${!cmdVarName} | sed "s|%FILE%|$file|")

            echo $aftercopy_cmd
            $aftercopy_cmd
        else
            echo no WOCR_AFTERCOPYCMD command set.
        fi

        cmdVarName="WOCR_AFTERDELCMD"
        if [ ! -z "$subdirectory" ]; then
            cmdVarName="WOCR_AFTERDELCMD_$subdirectory"
            if [ -z ${!cmdVarName} ]; then
                echo $cmdVarName is not set. Using default.
                cmdVarName="WOCR_AFTERDELCMD"
            fi
        fi

        if [ ! -z "${!cmdVarName}" ]; then
            afterdel_cmd=$(echo ${!cmdVarName} | sed "s|%FILE%|$file|")

            echo $afterdel_cmd
            $afterdel_cmd
        else
            echo no WOCR_AFTERDELCMD command set.
        fi

        rm $fullfile
    done
