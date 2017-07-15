#!/bin/bash

if [ -z ${TARGET_YEAR+x} ]; then
    echo "env TARGET_YEAR=YYYY is required."
    exit 1
fi

if [ -z ${MLIT_GO_JP_ENDPOINT+x} ]; then
    echo "env MLIT_GO_JP_ENDPOINT is not set. Downloading shapefiles would be failed unless it's already done."
fi

workdir=$(dirname "$0")
tmpdir=$workdir/tmp



# Download shape files
for i in {1..47}
do
    file=$(printf "%s/%02d_%04d.zip" $tmpdir $i $TARGET_YEAR)
    url=$(printf $MLIT_GO_JP_ENDPOINT $i)
    if ! [ -f $file ]; then
        curl -o $file $url
    else
        echo "${file} exists, no need to download"
    fi
done

for i in {1..47}
do
    file=$(printf "%s/%02d_%04d.zip" $tmpdir $i $TARGET_YEAR)
    name=$(printf "%02d_%04d" $i $TARGET_YEAR)

    if [ -f $tmpdir/$name-topo.json ]; then
        echo "Skip shp2json --> geo2topo for ${name}-topo.json"
        continue
    fi

    unzip -o -j $file -d $tmpdir/$name
    # Yes, it's not in UTF-8
    shp2json -n --encoding sjis $tmpdir/$name/*.shp -o $tmpdir/$name/$name.ndjson

    # `N03_007` field contains unique 5 digits code for each city
    # Unfortunately there's no official page in English though
    # http://www.soumu.go.jp/denshijiti/code.html
    #
    # There are some areas without the code such as land fill in Tokyo.
    ndjson-map 'd.id = d.properties.N03_007, d' < $tmpdir/$name/$name.ndjson \
        | ndjson-filter 'd.id' \
        | ndjson-map 'delete d.properties, d' > $tmpdir/$name/$name-id.ndjson

    geo2topo -n cities=$tmpdir/$name/$name-id.ndjson > $tmpdir/$name-topo.json
done

for i in {1..47}
do
    name=$(printf "%02d_%04d" $i $TARGET_YEAR)

    if [ -f $tmpdir/$name-geo.json ]; then
        echo "skip toposimplify --> topo2geo for ${name}-topo.json"
        continue
    fi

    echo "Simplify ${name}-topo.json and convert to geojson again..."
    # Change `-p` to closer to 0 to have more detailed boundaries.
    # Without this simplification, the file size would be too large geo2topo would be failed.
    toposimplify -p 0.0000001 -f < $tmpdir/$name-topo.json \
        | topo2geo cities=$tmpdir/$name-geo.json
done

if ! [ -f $tmpdir/japan-${TARGET_YEAR}.json ]; then
    echo "Merge all the topojson files into a single file..."
    geojson-merge $tmpdir/*_${TARGET_YEAR}-geo.json > $tmpdir/japan-${TARGET_YEAR}.json
fi

# toposimplify 0.000002 nearly perfect even at high zoom level but file size jumps up to 1.5MB
#               0.00002 gap becomes recognizable (751KB)
#                0.0002 has only 461KB but Tokyo area clearly looks oversimplified
# topoquantize 1e3 becomes almost likes LEGO blocks
echo "Convert to TopoJSON and simplify it..."
mkdir -p jp
geo2topo cities=$tmpdir/japan-${TARGET_YEAR}.json \
    | toposimplify -p 0.000002 -f \
    | topoquantize 1e4 \
    > $workdir/jp/japan-${TARGET_YEAR}-topo.json

# We do not include the below commands until we solve an exterior rings issue.
#    | topomerge prefectures=cities -k 'd.id.slice(0, 2)' -f 'd.id' \
#    | topomerge nation=prefectures \


toposimplify -p 0.0002 -f < $workdir/jp/japan-${TARGET_YEAR}-topo.json > $workdir/jp/japan-${TARGET_YEAR}-topo.low.json

ls -l $workdir/jp