module "vpc" {
    source = "terraform-aws-modules/vpc/aws"
    name = "my-vpc"
    cidr = "10.0.0.0/16"
    azs             = ["us-east-1a", "us-east-1b"]
    private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
    public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
    enable_nat_gateway = true
    single_nat_gateway = false  # You have 2 NAT gateways based on your output
    enable_dns_hostnames = true
    
    private_subnet_tags = {
        "kubernetes.io/cluster/terra-action" = "shared"
        "kubernetes.io/role/internal-elb" = "1"
    }
    public_subnet_tags = {
        "kubernetes.io/cluster/terra-action" = "shared"
        "kubernetes.io/role/elb" = "1"
    }
    tags = {
        Terraform = "true"
        Environment = "dev"
    }
}

module "eks" {
    source  = "terraform-aws-modules/eks/aws"
    version = "~> 21.0"
    
    name       = "terra-action"
    kubernetes_version = 1.31 
    
    endpoint_public_access = true
    endpoint_private_access = true
    
    enable_cluster_creator_admin_permissions = true

    addons = {
        coredns                = {}
        eks-pod-identity-agent = {
        before_compute = true
        }
        kube-proxy             = {}
        vpc-cni                = {
        before_compute = true
        }
    }
    
    eks_managed_node_groups = {
        terra-nodes = {
            instance_types = ["c7i-flex.large"]
            ami_type       = "AL2_x86_64"
            min_size       = 1
            max_size       = 3
            desired_size   = 2
        }
    }
    
    vpc_id     = module.vpc.vpc_id
    subnet_ids = module.vpc.private_subnets
    
    tags = {
        Environment = "dev"
        Terraform   = "true"
    }
}

# EBS CSI Driver IAM Role
data "aws_iam_policy" "ebs_csi_policy" {
    arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
    source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
    version = "5.39.0"
    
    create_role                   = true
    role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
    provider_url                  = module.eks.oidc_provider
    role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
    oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}