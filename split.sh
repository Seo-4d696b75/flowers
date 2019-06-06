# usage: $ ./split.sh {label1} [{label2}...]
# load variables
source variables.sh
# ruby splits image set into 
#     set for test
#     set for traing
# in random
ruby utils.rb --split $GCS_PATH $*
# upload split image set and its list to Google Cloud Storage
echo "==== upload =============================="
gsutil cp "./dict.txt" "${GCS_PATH}/dict.txt"
gsutil cp "./eval_set.csv" "${GCS_PATH}/eval_set.csv"
gsutil cp "./train_set.csv" "${GCS_PATH}/train_set.csv"