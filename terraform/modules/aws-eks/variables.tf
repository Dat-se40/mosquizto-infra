variable "cluster-name" {
  type = string
}

variable "subnet-ids" {
  type = list(string)
}

variable "node-instance-type" {
  type    = string
  default = "t3.medium"
}

variable "use-lab-role" {
  type    = bool
  default = true
}