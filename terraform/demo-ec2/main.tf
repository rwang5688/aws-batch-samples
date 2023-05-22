provider "aws" {
  region = local.region
}

locals {
  region = "us-east-2"
  name   = "batch-test-${replace(basename(path.cwd), "_", "-")}"

  tags = {
    Name       = local.name
    Example    = local.name
    Repository = "https://github.com/terraform-aws-modules/terraform-aws-batch"
  }
}

data "aws_region" "current" {}

################################################################################
# Batch Module
################################################################################

module "batch_disabled" {
  source  = "terraform-aws-modules/batch/aws"
  version = "~> 2.0.1"

  create = false
}

module "batch" {
  source  = "terraform-aws-modules/batch/aws"
  version = "~> 2.0.1"

  instance_iam_role_name        = "${local.name}-ecs-instance"
  instance_iam_role_path        = "/batch/"
  instance_iam_role_description = "IAM instance role/profile for AWS Batch ECS instance(s)"
  instance_iam_role_additional_policies = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
  instance_iam_role_tags = {
    ModuleCreatedRole = "Yes"
  }

  service_iam_role_name        = "${local.name}-batch"
  service_iam_role_path        = "/batch/"
  service_iam_role_description = "IAM service role for AWS Batch"
  service_iam_role_tags = {
    ModuleCreatedRole = "Yes"
  }

  create_spot_fleet_iam_role      = true
  spot_fleet_iam_role_name        = "${local.name}-spot"
  spot_fleet_iam_role_path        = "/batch/"
  spot_fleet_iam_role_description = "IAM spot fleet role for AWS Batch"
  spot_fleet_iam_role_tags = {
    ModuleCreatedRole = "Yes"
  }

  compute_environments = {
    small_ec2 = {
      name_prefix = "small_ec2"

      compute_resources = {
        type           = "EC2"
        min_vcpus      = 0
        max_vcpus      = 64
        desired_vcpus  = 0
        instance_types = ["m6i.4xlarge", "c6i.4xlarge", "r6i.4xlarge"]

        security_group_ids = [module.vpc_endpoint_security_group.security_group_id]
        subnets            = module.vpc.private_subnets

        # Note - any tag changes here will force compute environment replacement
        # which can lead to job queue conflicts. Only specify tags that will be static
        # for the lifetime of the compute environment
        tags = {
          # This will set the name on the Ec2 instances launched by this compute environment
          Name = "${local.name}-small"
          Type = "Ec2"
        }
      }
    }

    large_ec2 = {
      name_prefix = "large_ec2"

      compute_resources = {
        type           = "EC2"
        min_vcpus      = 0
        max_vcpus      = 128
        desired_vcpus  = 0
        instance_types = ["m6i.8xlarge", "c6i.8xlarge", "r6i.8xlarge"]

        security_group_ids = [module.vpc_endpoint_security_group.security_group_id]
        subnets            = module.vpc.private_subnets

        # Note - any tag changes here will force compute environment replacement
        # which can lead to job queue conflicts. Only specify tags that will be static
        # for the lifetime of the compute environment
        tags = {
          # This will set the name on the Ec2 instances launched by this compute environment
          Name = "${local.name}-large"
          Type = "Ec2"
        }
      }
    }
  }

  # Job queus and scheduling policies
  job_queues = {
    small_job_queue_1 = {
      name     = "SmallJobQueue1"
      state    = "ENABLED"
      priority = 1

      compute_environments  = ["small_ec2"]
      scheduling_policy_arn = null

      tags = {
        JobQueue = "Small job queue 1"
      }
    }

    small_job_queue_2 = {
      name     = "SmallJobQueue2"
      state    = "ENABLED"
      priority = 2

      compute_environments  = ["small_ec2"]
      scheduling_policy_arn = null

      tags = {
        JobQueue = "Small job queue 2"
      }
    }

    large_job_queue_98 = {
      name     = "LargeJobQueue98"
      state    = "ENABLED"
      priority = 98

      compute_environments  = ["large_ec2"]
      scheduling_policy_arn = null

      tags = {
        JobQueue = "Large job queue 98"
      }
    }

    large_job_queue_99 = {
      name     = "LargeJobQueue99"
      state    = "ENABLED"
      priority = 99

      compute_environments  = ["large_ec2"]
      scheduling_policy_arn = null

      tags = {
        JobQueue = "Large job queue 99"
      }
    }
  }

  job_definitions = {
    small_job = {
      name           = "${local.name}-small-job"
      propagate_tags = true

      container_properties = jsonencode({
        command = ["ls", "-la"]
        image   = "public.ecr.aws/runecast/busybox:1.33.1"
        resourceRequirements = [
          { type = "VCPU", value = "1" },
          { type = "MEMORY", value = "1024" }
        ]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.this.id
            awslogs-region        = local.region
            awslogs-stream-prefix = local.name
          }
        }
      })

      attempt_duration_seconds = 60
      retry_strategy = {
        attempts = 3
        evaluate_on_exit = {
          retry_error = {
            action       = "RETRY"
            on_exit_code = 1
          }
          exit_success = {
            action       = "EXIT"
            on_exit_code = 0
          }
        }
      }

      tags = {
        JobDefinition = "${local.name}-small-job"
      }
    }

    large_job = {
      name           = "${local.name}-large-job"
      propagate_tags = true

      container_properties = jsonencode({
        command = ["ls", "-la"]
        image   = "public.ecr.aws/runecast/busybox:1.33.1"
        resourceRequirements = [
          { type = "VCPU", value = "1" },
          { type = "MEMORY", value = "1024" }
        ]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.this.id
            awslogs-region        = local.region
            awslogs-stream-prefix = local.name
          }
        }
      })

      attempt_duration_seconds = 60
      retry_strategy = {
        attempts = 3
        evaluate_on_exit = {
          retry_error = {
            action       = "RETRY"
            on_exit_code = 1
          }
          exit_success = {
            action       = "EXIT"
            on_exit_code = 0
          }
        }
      }

      tags = {
        JobDefinition = "${local.name}-large-job"
      }
    }
  }

  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0"

  name = local.name
  cidr = "10.99.0.0/18"

  azs             = ["${local.region}a", "${local.region}b", "${local.region}c"]
  public_subnets  = ["10.99.0.0/24", "10.99.1.0/24", "10.99.2.0/24"]
  private_subnets = ["10.99.3.0/24", "10.99.4.0/24", "10.99.5.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_route_table_tags  = { Name = "${local.name}-public" }
  public_subnet_tags       = { Name = "${local.name}-public" }
  private_route_table_tags = { Name = "${local.name}-private" }
  private_subnet_tags      = { Name = "${local.name}-private" }

  enable_dhcp_options      = true
  enable_dns_hostnames     = true
  dhcp_options_domain_name = data.aws_region.current.name == "us-east-2" ? "ec2.internal" : "${data.aws_region.current.name}.compute.internal"

  tags = local.tags
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 4.0"

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [module.vpc_endpoint_security_group.security_group_id]

  endpoints = {
    ecr_api = {
      service             = "ecr.api"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    }
    ecr_dkr = {
      service             = "ecr.dkr"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    }
    ecs = {
      service             = "ecs"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    }
    ssm = {
      service             = "ssm"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    }
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
    }
  }

  tags = local.tags
}

module "vpc_endpoint_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = "${local.name}-vpc-endpoint"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress_with_self = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Container to VPC endpoint service"
      self        = true
    },
  ]

  egress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules       = ["https-443-tcp"]

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/batch/${local.name}"
  retention_in_days = 1

  tags = local.tags
}
