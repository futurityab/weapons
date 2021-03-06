#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#

WRANGLER_SEGS=/usr/local/memex/wrangler_crawl/production
WRANGLER_ARCH=/usr/local/memex/wrangler_crawl/archive
CORE=imagecatdev

NUTCH_SNAPSHOT=/data2/USCWeaponsStatsGathering/nutch/runtime/local
FULL_DUMP_PATH=/data2/USCWeaponsStatsGathering/nutch/full_dump
DELTA_UPDATES=/usr/local/memex/wrangler_crawl/deltaUpdates
NUTCH_TIKA_SOLR=/usr/local/memex/imagecat/tmp/parser-indexer/target

cd /data2/USCWeaponsStatsGathering/nutch
find $WRANGLER_SEGS -type d -name "segments" > wrangler_segments.txt
echo "Dumping Segments Now"
./wrangler_batch_dump.sh wrangler_segments.txt $NUTCH_SNAPSHOT
echo "Dump complete, Obtaining Delta updates/docIDs of fileDumper"

cd $NUTCH_SNAPSHOT/logs
today=$(date +"%Y-%m-%d")
updates=$today"DocIDs.txt"
# to re-ingest Dumped Docs, change Writing to Skipping 
cat hadoop.log | grep Writing | grep $today | grep full_dump | grep -o /data2[^]]* > $DELTA_UPDATES/$updates

echo "Chunking docIDs to parallelize Ingestion"
cd $DELTA_UPDATES
mkdir partFiles
split -l 50000 $updates partFiles/parts

echo "Starting Ingestion with parser-indexer"
source /usr/local/memex/jdk8.sh
# Choose relevant timeout value for Tika Parsers default 1 min
ls partFiles/* | while read i ; do echo "sleep 5; echo $i; java -jar $NUTCH_TIKA_SOLR/nutch-tika-solr-1.0-SNAPSHOT.jar postdump -solr http://localhost:8983/solr/$CORE -list $i -threads 1 -timeout 60000 > $i.out & " ; done > cmd.txt
echo "wait" >> cmd.txt
cat cmd.txt | bash

echo "Ingestion COMPLETE, removing chunked docIDs to avoid future reIngestion"
rm -rf partFiles/

cd /data2/USCWeaponsStatsGathering/nutch
find $WRANGLER_SEGS -type d -name "2016*" > wrangler_segments.txt

echo "Starting parser indexer for Outlinks"
java -jar $NUTCH_TIKA_SOLR/nutch-tika-solr-1.0-SNAPSHOT.jar outlinks -list wrangler_segments.txt -solr http://localhost:8983/solr/$CORE -nutch $NUTCH_SNAPSHOT -dumpRoot $FULL_DUMP_PATH

echo "Starting parser indexer for Timestamps"
java -jar $NUTCH_TIKA_SOLR/nutch-tika-solr-1.0-SNAPSHOT.jar lastmodified -solr http://localhost:8983/solr/$CORE -list wrangler_segments.txt -dumpRoot $FULL_DUMP_PATH

echo "Archiving Wrangler Segments"
mv $WRANGLER_SEGS/* $WRANGLER_ARCH/
