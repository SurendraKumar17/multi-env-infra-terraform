env          = "prod"
project      = "microservices"
region       = "us-east-1"
cluster_name = "prod-eks-cluster"
max_size     = 3
desired_size = 1
min_size     = 1

kong_version       = "2.38.0"
kong_replica_count = 1