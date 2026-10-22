output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "public_subnet_id" {
  value = aws_subnet.public_subnet1.id
}

output "public_subnet_ids" {
  value = [aws_subnet.public_subnet1.id, aws_subnet.public_subnet2.id]
}