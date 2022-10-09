#!/bin/sh

# Sunverge Live Data Capture Script with Re-Upload to Charge HQ
# requires curl, bc, jq

# IMPORTANT: Set the 3 parameters below for this script to function
user=' '
pass=' '
siteId=' '

# Sunverge / Vector NZ specific parameters
site='vector'
initial_url='https://sis.sunverge.com/marge/consumer/'$site'/logon.html'
key_url='https://sis.sunverge.com/marge/consumer/'$site'/index.html'
logout_url='https://sis.sunverge.com/marge/saml/logout?local=true'
per='false' # change to 'true' for extra historic performance data for the last d/m/y

# Charge HQ specific parameters
api_endpoint='https://api.chargehq.net/api/site-meters'
upload_frequency=60 # seconds (minimum 30)

usage_text='Usage: '$0' [-h, --help] [-q, --quiet]'
usage() { echo $usage_text 1>&2; exit 1; }

SHORT=hq
LONG=help,quiet

OPTS=$(getopt --options $SHORT --long $LONG --name "$0" -- "$@")

if [ $? != 0 ] ; then usage; fi
eval set -- "$OPTS"

while true ; do
  case "$1" in
    -h | --help ) HELP="true"; shift ;;
    -q | --quiet ) QUIET="true"; shift ;;
    -- ) shift; break ;;
    * ) usage ;;
  esac
done

if [ "$QUIET" != "true" ] ; then echo '\nSunverge Live Data Capture Script with Re-Upload to Charge HQ \n\n'$usage_text'\n' ; fi

if [ "$HELP" = "true" ] || [ "$QUIET" != "true" ] ; then
  echo '   -h, --help  shows this help screen'
  echo '   -q, --quiet supress extraneous text\n'
  echo 'This is a Sunverge data capture script, specfic to Vector New Zealand. The script uses Curl to login to Sunverge website and then captures live solar generation data before re-formatting it and uploading the data to ChargeHQ. \n'
  echo 'The following fields MUST BE MODIFIED in the script in order to function correctly. \n'
  echo '[1] user   : username from your Sunverge/Vector account'
  echo '[2] pass   : password from your Sunverge/Vector account'
  echo '[3] siteId : from ChargeHQ (email Jay to get yours). This is necessary to link the ChargeHQ Push API to your ChargeHQ account \n'
  echo 'By default, the script waits '$upload_frequency' seconds before uploading and the re-uploads data approximately every '$upload_frequency' seconds continuously after that. This may be modified as required, but the period between uploads must be no shorter than 30 seconds (requirement by ChargeHQ API) \n'
fi

if [ "$HELP" = "true" ] || [ "$user" = " " ] || [ "$pass" = " " ] || [ "$siteId" = " " ] ; then exit 1 ; fi

if [ "$QUIET" != "true" ] ; then echo 'Repeats forever. <CTL-C> to exit \nPlease wait '$upload_frequency' seconds ... \n' ; fi

instances=$( ps -efl --no-heading | grep $0 | grep -v grep | wc -l )
if [ $instances -gt 2 ] ; then echo 'Already running kill old process first. \n' ; exit 1 ; fi

D=$HOME/.$site
if [ ! -d "$D" ]; then mkdir $D; fi
if [ -f ''$D'/cookie.txt' ]; then rm ''$D'/cookie.txt'; fi


logon_function(){
initial=$( curl $initial_url --cookie ''$D'/cookie.txt' --cookie-jar ''$D'/cookie.txt' --include --silent --compressed ) > /dev/null
csrf=$( echo $initial | sed -n -e 's/^.*"_csrf" value="//p' | cut -d '"' -f 1 )
sessionrequest=$( cat ''$D'/cookie.txt' | grep SESSION | sed -n -e 's/^.*SESSION\t//p' )

logon=$( curl $initial_url -H 'cookie: SESSION='$sessionrequest'' --cookie-jar ''$D'/cookie.txt' --include --silent --data-raw 'emailAddress='$user'&password='$pass'&keepLoggedIn=on&_csrf='$csrf'' --compressed ) > /dev/null
logoncookie=$( cat $D/cookie.txt | grep Logon | sed -n -e 's/^.*Logon\t//p' )
session=$( echo $logon | sed  -n -e 's/^.*SESSION=//p' | cut -d ';' -f 1 )

# Grab Sunverge key from $keyvalue [ key is same every time, so could be hard coded after first use ]
# Example data below:
# svrg.consumermain.init("vector", "/marge", "false", "DD MMM", "DD MMM YYYY", "extracted-sunverge-key-value", "performancePanelSolarUsageLabel",...
# extracted keyvalue="extracted-sunverge-key-value"

key=$( curl $key_url -H 'cookie: site='$site'; SESSION='$session'; Logon='$logoncookie'' --include --silent --compressed ) > /dev/null
keyvalue=$( echo $key | grep -o "svrg.consumermain.init.*" | cut -d '"' -f 12 )

} # /logon_function()


livedata_function(){

livedata=$( curl 'https://sis.sunverge.com/marge/consumer/data.json?cur=true&per='$per'&fpi='$keyvalue'&site='$site'' -H 'cookie: SESSION='$session'; '$logoncookie'' -H 'x-csrf-token: '$csrf'' --silent --compressed ) > /dev/null

} # /livedata_function()


printdata_function(){

# Expect Sunverge live data in the JSON format below
# { "consumerUiDataModel" : { "currentActivity" : { "communicationConnected" : true, "battAvailKwh" : 2.328, "currentEnergyCharges" : null, "battTotalKwh" : 9.312, "batt2Grid" : { "pollDate" : 1664830806000, "kw" : 0.0, "show" : false }, "batt2Site" : { "pollDate" : 1664830806000, "kw" : 0.0, "show" : false }, "grid2Batt" : { "pollDate" : 1664830806000, "kw" : 0.0, "show" : false }, "grid2Site" : { "pollDate" : 1664830806000, "kw" : 0.2, "show" : true }, "pv2Batt" : { "pollDate" : 1664830806000, "kw" : 1.0, "show" : true }, "pv2Grid" : { "pollDate" : 1664830806000, "kw" : 0.0, "show" : false }, "pv2Site" : { "pollDate" : 1664830806000, "kw" : 0.0, "show" : false }, "siteUsage" : 0.2, "pvProd" : 1.0, "sisPowerPcnt" : 100 }, "performance" : null, "status" : { "isEvChargerConfigured" : false, "upsTimeRemainingText" : "2147483647", "upsTimeRemaining" : "2147483647", "inUpsMode" : false, "inErrorMode" : false } } }

# extract live data
tsms=$( echo $livedata | jq .consumerUiDataModel.currentActivity.batt2Grid.pollDate )
pv2batt=$( echo $livedata | jq .consumerUiDataModel.currentActivity.pv2Batt.kw )
pv2grid=$( echo $livedata | jq .consumerUiDataModel.currentActivity.pv2Grid.kw )
batt2site=$( echo $livedata | jq .consumerUiDataModel.currentActivity.batt2Site.kw )
grid2site=$( echo $livedata | jq .consumerUiDataModel.currentActivity.grid2Site.kw )
grid2batt=$( echo $livedata | jq .consumerUiDataModel.currentActivity.grid2Batt.kw )
batt2grid=$( echo $livedata | jq .consumerUiDataModel.currentActivity.batt2Grid.kw )
batttotalkwh=$( echo $livedata | jq .consumerUiDataModel.currentActivity.battTotalKwh )
production_kw=$( echo $livedata | jq .consumerUiDataModel.currentActivity.pvProd )
consumption_kw=$( echo $livedata | jq .consumerUiDataModel.currentActivity.siteUsage )
battery_energy_kwh=$( echo $livedata | jq .consumerUiDataModel.currentActivity.battAvailKwh )

# some addional calcs
grid_usage=`echo $grid2site+$grid2batt | bc -l | xargs printf "%.1f"`
battery_usage=`echo $batt2site+$batt2grid | bc -l | xargs printf "%.1f"`
export_usage=`echo $pv2grid+$batt2grid | bc -l | xargs printf "%.1f"`
battery_soc=`echo $battery_energy_kwh/$batttotalkwh | bc -l | xargs printf "%.4f"`
battery_charge_rate=`echo $pv2batt+$grid2batt | bc -l | xargs printf "%.1f"`

if [ `echo "$grid_usage > 0" | bc` -eq "1" ] ; then net_import_kw=$grid_usage ; else
  if [ `echo "$export_usage > 0" | bc` -eq "1" ] ; then net_import_kw=-$export_usage ; else net_import_kw=0; fi
fi

if [ `echo "$battery_usage > 0" | bc` -eq "1" ] ; then battery_discharge_kw=$battery_usage ; else
  if [ `echo "$battery_charge_rate > 0" | bc` -eq "1" ] ; then battery_discharge_kw=-$battery_charge_rate ; else battery_discharge_kw=0; fi
fi

# create new JSON payload for ChargeHQ
JSON_payload={\"siteId\":'"'$siteId'"',\"tsms\":$tsms,\"siteMeters\":{\"production_kw\":$production_kw,\"net_import_kw\":$net_import_kw,\"consumption_kw\":$consumption_kw,\"battery_discharge_kw\":$battery_discharge_kw,\"battery_soc\":$battery_soc,\"battery_energy_kwh\":$battery_energy_kwh}}

} # /printdata_function()


uploadjson_function(){

#upload new JSON payload to ChargeHQ
payload_delivery=$( curl -X POST -H 'Content-Type: application/json' -d $JSON_payload $api_endpoint --silent ) > /dev/null
echo -n `date`; echo ' JSON payload = '$JSON_payload''

} # /uploadjson_function()


logout_function(){
echo '\nLogging out...'
logout=$( curl $logout_url -H 'cookie: SESSION='$session'; Logon='$logoncookie'' --include --silent --compressed ) > /dev/null
if [ -f ''$D'/cookie.txt' ]; then rm ''$D'/cookie.txt'; fi
exit 0
break
} # /logout_function()


# main
trap logout_function INT
logon_function
while true; do
  for i in `seq 1 $upload_frequency`; do
    sleep 1 ;
  done
  livedata_function
  printdata_function
  uploadjson_function
done
logout_function
