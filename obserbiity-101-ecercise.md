cd April26-bootcamp/microservices/helm-deployments-kind/helm-ms-simple

# bring up kind clusetr with local microservice and services with below script 

./helm-deploy.sh

once app is up, we ca setup observibiity using grafana, primethus, loki, promtail

cd April26-bootcamp/microservices/observibility-normal

./deploy-observability.sh