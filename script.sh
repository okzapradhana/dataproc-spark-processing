#!/bin/bash

#Declare Variables
TEMPLATE=bash-workflow-template-pyspark-15
REGION=asia-southeast1
ZONE=asia-southeast1-a
PROJECT_ID=static-gravity-312212
CLUSTER_NAME=pyspark-jupyter-gcs-to-bigquery-cluster
BUCKET_NAME=spark-jupyter-bucket-312212
WORKFLOW_BUCKET_NAME=flight-sparks-w3

#Rename file and copy them from local to GCS
for filename in ./input/*.json
do
  EXTRACTED_FILENAME=$(echo $filename | grep -Eo '[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}')
  DATE_ADDED=$(date -d "$EXTRACTED_FILENAME +723 days" '+%Y-%m-%d')
  gsutil cp ${filename} gs://${BUCKET_NAME}/input/${DATE_ADDED}.json
done

#Set project ID
gcloud config set project ${PROJECT_ID}

#Create Bucket
gsutil mb -c standard -l ${REGION} gs://${BUCKET_NAME}

#Create Cluster
gcloud beta dataproc clusters create ${CLUSTER_NAME} \
  --region=${REGION} \
  --zone=${ZONE} \
  --single-node \
  --master-machine-type=n1-standard-2 \
  --bucket=${BUCKET_NAME} \
  --image-version=1.5-ubuntu18 \
  --optional-components=ANACONDA,JUPYTER \
  --enable-component-gateway \
  --metadata 'PIP_PACKAGES=google-cloud-bigquery google-cloud-storage' \
  --initialization-actions gs://goog-dataproc-initialization-actions-${REGION}/python/pip-install.sh

#Submit job to cluster
gcloud beta dataproc jobs submit pyspark gs://${WORKFLOW_BUCKET_NAME}/jobs/spark_etl_job.py \
  --cluster=${CLUSTER_NAME} \
  --region=${REGION} \
  --jars=gs://spark-lib/bigquery/spark-bigquery-latest_2.12.jar

#Delete cluster after finished all works to prevent you got bill charged
gcloud beta dataproc clusters delete ${CLUSTER_NAME} \
  --region=${REGION}

#Alternatively we can use workflow-template to run Spark code
gcloud beta dataproc workflow-templates create ${TEMPLATE} \
  --region=${REGION}

gcloud beta dataproc workflow-templates set-managed-cluster ${TEMPLATE} \
  --region=${REGION} \
  --bucket=${WORKFLOW_BUCKET_NAME} \
  --zone=${ZONE} \
  --cluster-name="bash-wf-template-pyspark-cluster" \
  --single-node \
  --master-machine-type=n1-standard-2 \
  --image-version=1.5-ubuntu18

gcloud beta dataproc workflow-templates add-job pyspark gs://${WORKFLOW_BUCKET_NAME}/jobs/spark_etl_job.py \
  --step-id="bash-pyspark-wf-template-gcs-to-bq" \
  --workflow-template=${TEMPLATE} \
  --region=${REGION} \
  --jars=gs://spark-lib/bigquery/spark-bigquery-latest_2.12.jar

gcloud beta dataproc workflow-templates instantiate ${TEMPLATE} \
  --region=${REGION}