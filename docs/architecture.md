# Architecture — VoicePay Platform

## Overview

VoicePay is a cloud-native platform built on AWS using Terraform for infrastructure provisioning.

The platform is designed with:
- Modular infrastructure (Terraform modules)
- Multi-environment isolation (dev, staging, prod)
- Secure access via IAM and OIDC
- Containerized workloads deployed on EKS

---

## High-Level Architecture

Core components:

- VPC (networking layer)
- EKS (Kubernetes cluster)
- ECR (container registry)
- IAM (access control)
- S3 + DynamoDB (Terraform state backend)

---

## Component Breakdown

### VPC
- Multi-AZ design
- Public and private subnets
- Internet Gateway
- Optional NAT Gateway (disabled in dev for cost)

---

### EKS
- Managed Kubernetes cluster
- Node groups with configurable scaling
- OIDC provider enabled for IRSA

---

### ECR
- Centralized repositories (no duplication per environment)
- Image tagging via commit SHA
- Lifecycle policy for cost control

---

### IAM
- Least privilege roles
- CI/CD access via GitHub OIDC
- IRSA roles for Kubernetes workloads

---

### Terraform Backend
- S3 bucket for state storage
- DynamoDB table for state locking

---

## Design Decisions

### 1. Shared ECR Repositories
Instead of per-environment repos:
- voicepay-auth-dev ❌
- voicepay-auth-prod ❌

We use:
- voicepay-auth ✅

Environment separation handled via image tags.

---

### 2. Cost Optimization
- NAT Gateway disabled in dev
- Lifecycle policies for ECR and S3
- Manual apply for production

---

### 3. Security
- No long-lived AWS credentials
- OIDC-based authentication for CI/CD
- IAM scoped to least privilege

---

## Future Improvements

- Observability (logs, metrics, alerts)
- Drift detection automation
- Policy enforcement (OPA / Conftest)
- GitOps deployment (ArgoCD)

---

## Summary

The platform is designed to be:
- Scalable
- Secure
- Cost-efficient
- Production-ready