# sunverge2chargehq

Sunverge Live Data Capture Script with Re-Upload to Charge HQ

Usage: ./sunverge2chargehq.sh [-h, --help] [-q, --quiet]


   -h, --help  shows this help screen

   -q, --quiet supress extraneous text


This is a Sunverge data capture script, specfic to Vector New Zealand. The script uses Curl to login to Sunverge website and then captures live solar generation data before re-formatting it and uploading the data to ChargeHQ.

The following fields MUST BE MODIFIED in the script in order to function correctly.

[1] user   : username from your Sunverge/Vector account

[2] pass   : password from your Sunverge/Vector account

[3] siteId : from ChargeHQ (email Jay to get yours). This is necessary to link the ChargeHQ Push API to your ChargeHQ account

By default, the script waits 60 seconds before uploading and the re-uploads data approximately every 60 seconds continuously after that. This may be modified as required, but the period between uploads must be no shorter than 30 seconds (requirement by ChargeHQ API)
