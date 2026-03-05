# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Alibaba Cloud CLI automation project that wraps the official Alibaba Cloud CLI with enhanced functionality. The project provides a user-friendly interface for managing Alibaba Cloud resources with interactive selection, batch operations, and unified logging.

## Architecture

### Core Components
- `main.sh`: Entry point that routes commands to appropriate service modules
- `base_service.sh`: Core framework providing unified API calls, output formatting, error handling
- Service-specific modules (e.g., `ecs.sh`, `rds.sh`, `vpc.sh`): Individual service implementations
- `utils.sh`: Common utility functions for validation, logging, and dependency checks
- `config.sh`: Configuration management functions

### Framework Features
All services use a unified framework that provides:
- `call_aliyun_api`: Standardized API calls to Alibaba Cloud
- `generic_list`: Standardized list operations with consistent output formatting
- `generic_create/update/delete`: Standardized CRUD operations
- Unified error handling and logging
- Parameter validation and confirmation flows

### Service Module Structure
Each service module follows a standardized pattern:
1. Load the base framework (`source base_service.sh`)
2. Implement standard CRUD functions using framework helpers
3. Handle command routing via `handle_<service>_commands` function
4. Provide help information

All services have been migrated to use the framework according to `MIGRATION_STATUS.md`.

## Available Services

The project supports the following Alibaba Cloud services:
- **Compute**: ECS (instances, SSH keys), ACK (Kubernetes clusters)
- **Network**: VPC (networks, switches, security groups), EIP (public IPs), NAT, LBS (load balancers), DNS, Domain
- **Storage**: OSS (object storage), NAS (file storage)
- **Database**: RDS (relational DB), KVStore (Redis), PolarDB (cloud-native DB)
- **Other**: CDN, RAM (access control), CAS (certificate service), Cost/Balance management

## Development Commands

### Running the Tool
```bash
./main.sh [--profile <profile>] [--region <region>] <service> <operation> [parameters...]
```

### Common Operations
```bash
# List all services' resources
./main.sh list-all

# ECS management
./main.sh ecs list
./main.sh ecs create <instance-name> <instance-type> <image-id>
./main.sh ecs start <instance-id>
./main.sh ecs stop <instance-id>

# VPC management
./main.sh vpc list
./main.sh vpc create <name>

# RDS management
./main.sh rds list
./main.sh rds create <name> <engine> <version> <spec>

# Cost management
./main.sh balance list
./main.sh cost daily [YYYY-MM-DD]

# Configuration management
./main.sh config get
./main.sh config add <name> <access-key> <secret-key> [region]
```

### Output Formats
Most commands support multiple output formats:
- `human` (default): Human-readable format
- `json`: JSON format
- `tsv`: Tab-separated values

Example: `./main.sh ecs list json`

### Configuration
The project uses Alibaba Cloud CLI profiles stored in `$HOME/.aliyun/config.json`. Multiple profiles are supported.

## Key Files and Directories

- `main.sh`: Main entry point with command routing
- `base_service.sh`: Core framework with generic functions
- `utils.sh`: Utility functions for validation and logging
- `config.sh`: Configuration management
- `{service}.sh`: Individual service modules (ecs.sh, rds.sh, etc.)
- `service_template.sh`: Template for creating new service modules
- `FRAMEWORK_GUIDE.md`: Framework usage documentation
- `MIGRATION_STATUS.md`: Status of service migrations to the framework

## Adding New Services

To add a new service:
1. Copy `service_template.sh` and customize for the new service
2. Replace placeholders: SERVICE_NAME, SERVICE_DISPLAY_NAME, API_SERVICE
3. Adjust API calls according to Alibaba Cloud API documentation
4. Add route to the service in `main.sh` case statement
5. Use framework functions (generic_list, generic_create, etc.) for standard operations

## Testing

The project includes `test_migrated_services.sh` for testing migrated services functionality.

## Logging and Data

- All operations are logged to `data/<profile>/<region>/logs/`
- Resource data is saved to `data/<profile>/<region>/data/<service>/`
- Log rotation and cleanup should be implemented as needed