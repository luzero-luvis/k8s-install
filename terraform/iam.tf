data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "k8s_node" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVolumes",
      "ec2:DescribeVpcs",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "k8s_node" {
  name               = "${var.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = { Name = "${var.cluster_name}-node-role" }
}

resource "aws_iam_role_policy" "k8s_node" {
  name   = "${var.cluster_name}-node-policy"
  role   = aws_iam_role.k8s_node.id
  policy = data.aws_iam_policy_document.k8s_node.json
}

resource "aws_iam_instance_profile" "k8s_node" {
  name = "${var.cluster_name}-node-profile"
  role = aws_iam_role.k8s_node.name
}
