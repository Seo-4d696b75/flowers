# usage: $ ./image.sh {label} {url_list}
# downloaded images are to be stored here
mkdir $1
# ruby download images in multi-thread
ruby utils.rb --get $2 100 $1
# load variables
source variables.sh
# upload images to Google Cloud Storage
gsutil -m cp -r $1 "${GCS_PATH}/${1}"