# Create EC2 IAM role for worker instance.
resource "aws_iam_role" "worker_instance_role" {
  name = "${var.infra_id}-worker-role"
  path = "/"

  tags = merge(map(
  "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_role_policy" "worker_policy" {
  name = "${var.infra_id}-worker-policy"
  role = aws_iam_role.worker_instance_role.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "ec2:Describe*",
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_instance_profile" "worker_instance_profile" {
  name = "${var.infra_id}-worker-instance-profile"
  role = aws_iam_role.worker_instance_role.id
}