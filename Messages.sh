#! /usr/bin/env bash
find package kwin-script -name '*.qml' -print0 | xargs -0 "$XGETTEXT" -o "$podir/plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn.pot"
