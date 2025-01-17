#!/bin/bash

source ./buildconfig.sh

MUSTACHE="${MUSTACHE?-mustache}"

TMP_YML="$(mktemp)"
TMP_INI="$(mktemp)"

packagefull="$package"-"$build"
packagedir="."

cleanup() {
    ( cd "$utdir" && rm -r "$packagefull" )
}

( # Subshell to preserve original working dir
    cat "$makeini">"$TMP_INI"
    echo EditPackages="$packagefull">>"$TMP_INI"

    cd "$utdir"

    ( # Subshell to exit early on error, to go right into cleanup
        set -e

        mkdir "$packagefull"

        # Build temporary YAML file
        echo "build: '$build'" > "$TMP_YML"
        echo "name: '$name'" > "$TMP_YML"
        echo "version: '$version'" >> "$TMP_YML"
        echo "package: '$packagefull'" >> "$TMP_YML"
        echo "debug: '$debug'" >> "$TMP_YML"

        if [[ "$debug" == 1 ]]; then
            echo "namesuffix: ' ($build)'" >> "$TMP_YML"
        else
            echo "namesuffix: ''" >> "$TMP_YML"
        fi

        echo >> "$TMP_YML"
        cat "$package/template-options.yml" >> "$TMP_YML"

        # Copy assets
        for asset in Models Textures Sounds; do
            if [[ -d "$package"/"$asset" ]]; then
            cp -rv "$package"/"$asset" "$packagefull"
            fi
        done

        # Format classes with Mustache
        mkdir "$packagefull"/Classes

        for class in "$package"/Classes/**; do
            class="$(basename "$class")"
            echo "Formatting: $packagefull/Classes/$class"
            "$MUSTACHE" "$package/Classes/$class" < "$TMP_YML" > "$packagefull/Classes/$class"
        done

        # Build .u
        (
            cd System
            #WINEPREFIX="$wineprefix" wine "$umake" "$package-$build"
            if [[ -f "$packagefull.u" ]]; then rm "$packagefull.u"; fi
            echo "* Invoking ucc make in $(pwd)"
            "$ucc" make -NoBind ini="$TMP_INI" | tee "$packagedir/make.log"

            # Ensure .u is built
            if [[ ! -f "$packagefull.u" ]]; then
                if [[ -f "$HOME/.utpg/System/$packagefull.u" ]]; then
                    mv "$HOME/.utpg/System/$packagefull.u" .

                else
                    exit 1
                fi
            fi
        )
        code=$?; [[ $code == 0 ]] || exit $code

        # Format .int with Mustache
        echo "Formatting: System/$package.int"
        "$MUSTACHE" "$package/template.int" < "$TMP_YML" > "System/$packagefull.int"

        # Package up
        cp -f "$package/README.adoc" "Help/$package.adoc"
        tar cf "$packagefull.tar" "System/$packagefull.int" "System/$packagefull.u" "Help/$package.adoc"

        zip -9r "$packagefull.zip" "System/$packagefull.int" "System/$packagefull.u" "Help/$package.adoc" >/dev/null
        gzip --best -k "$packagefull.tar"
        bzip2 --best -k "$packagefull.tar"

        rm "$packagefull.tar"

        # Move to dist
        echo Packaging up...
        mkdir -p "$dist/$package/$build"
        mv "$packagefull."{tar.*,zip} "$dist/$package/$build"

        # Update dist/latest
        echo Organizing dist directory...
        mkdir -p "$dist/$package/latest"
        rm -f "$dist/$package/latest/"*
        cp "$dist/$package/$build/"* "$dist/$package/latest"
    )
    exit $?
)
code=$?

# Finish up

rm "$TMP_YML"
rm "$TMP_INI"

echo Cleaning up...
cleanup

exit $code