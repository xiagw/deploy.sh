# Code Refactoring Documentation

This document tracks the progress and steps of our code modularization efforts for the deployment script system.

## Completed Refactoring Steps

1. Repository Management (`lib/repo.sh`)
   - Handles repository-specific configuration, file management, and version control operations
   - Functions include:
     - Repository management:
       - `repo_inject_file`: Injects files and configurations into repository
       - `repo_language_detect`: Detects repository programming language
       - `determine_deployment_method`: Determines deployment strategy
     - Version control operations:
       - `setup_git_repo`: Git repository setup and management
       - `setup_svn_repo`: SVN repository setup and management
       - `get_git_branch`: Branch detection
       - `get_git_commit_sha`: Commit SHA retrieval
       - `get_git_last_commit_message`: Commit message retrieval
   - Features:
     - Centralized repository configuration management
     - Language detection and setup
     - Deployment method detection
     - Docker build configuration
     - Environment-specific file handling
     - Support for multiple VCS (Git, SVN)
     - Repository setup and configuration
     - Branch and commit management
     - Comprehensive error handling
   - Added proper error handling and logging

2. Notification System (`lib/notify.sh`)
   - Unified notification interface for multiple channels
   - Supports WeChat Work, Telegram, Element, and Email
   - Functions include:
     - `handle_notify`: Main interface for all channels
     - `notify_wecom`: WeChat Work notifications
     - `notify_telegram`: Telegram notifications
     - `notify_element`: Element notifications
     - `notify_email`: Email notifications
   - Added comprehensive documentation in `docs/notify.md`

3. System Maintenance (`lib/system.sh`)
   - Centralized system maintenance and cleanup operations
   - Functions include:
     - `system_clean_disk`: Clean up disk space when usage exceeds threshold
     - `update_nginx_geoip_db`: Nginx GeoIP database updates
     - `system_check`: Check system requirements and install dependencies
     - `system_cert_renew`: Renew SSL certificates with acme.sh
   - Handles:
     - Disk cleanup and Docker cleanup
     - System maintenance tasks
     - SSL certificate management
     - Nginx GeoIP database updates
     - System dependency checks
   - Features:
     - Normal and aggressive cleaning modes
     - Centralized certificate management
     - Clear renewal conditions
     - Integration with acme.sh
     - Comprehensive error handling and logging
     - Multi-server support

4. Common Utilities (`lib/common.sh`)
   - Core utility functions and logging interface
   - Functions include:
     - `_msg`: Core logging function with level-based filtering
     - `is_demo_mode`: Check if running in demo mode
     - `is_china`: Check if running in China region
   - Features:
     - Timestamp-based logging
     - Log level filtering
     - Color-coded console output
     - Automatic log file management
     - Configurable log levels
     - Common utility functions
   - Added comprehensive error handling and documentation

5. Code Analysis (`lib/analysis.sh`)
   - Centralized code analysis and quality checks
   - Functions include:
     - `analysis_sonarqube`: Code quality analysis with SonarQube
     - `analysis_gitleaks`: Security scanning for sensitive information
     - `analysis_zap`: Security scanning with OWASP ZAP
     - `analysis_vulmap`: Security scanning with Vulmap
     - `generate_apidoc`: API documentation generation with apidoc

6. Kubernetes Management (`lib/kubernetes.sh`)
   - Handles Kubernetes cluster operations
   - Functions include:
     - `kube_config_init`: Initialize Kubernetes configuration
     - `kube_setup`: Setup Kubernetes cluster using Terraform
     - `create_helm_chart`: Creates and configures Helm charts
   - Features:
     - Independent cluster creation logic
     - Terraform integration
     - Error handling and logging
     - Non-blocking main process design
     - Flexible Helm chart configuration
     - Support for TCP/HTTP protocols
     - Automatic volume and mount configuration
     - DNS configuration management
   - Added validation for Terraform directory
   - Clear success/failure messaging

7. Deployment Operations (`lib/deployment.sh`)
   - Core deployment logic for multiple deployment methods
   - Functions include:
     - `deploy`: Main deployment orchestration function
     - `deploy_aliyun_functions`: Aliyun Functions deployment
     - `deploy_to_kubernetes`: Kubernetes deployment with Helm
     - `deploy_via_rsync_ssh`: Rsync+SSH deployment
     - `deploy_aliyun_oss`: Aliyun OSS deployment
     - `deploy_rsync`: Rsync server deployment
     - `deploy_ftp`: FTP deployment
     - `deploy_sftp`: SFTP deployment
     - `deploy_notify`: Deployment notifications
   - Features:
     - Unified deployment interface
     - Multiple deployment methods support
     - Flexible configuration options
     - Comprehensive error handling
     - Deployment status notifications
   - Added proper error handling and logging

8. Testing Framework (`lib/test.sh`)
   - Centralized testing functionality
   - Functions include:
     - `test_unit`: Executes unit tests
     - `test_function`: Executes functional tests
   - Features:
     - Flexible test script location support
     - Clear success/failure reporting
     - Comprehensive error handling
     - Integration with project-specific and global test scripts
   - Added proper logging and status reporting

9. Docker Operations (`lib/docker.sh`)
    - Handles all Docker-related operations
    - Functions include:
      - `docker_login`: Manages Docker registry authentication
      - `get_docker_context`: Handles Docker context selection and management
      - `build_image`: Builds Docker images with support for base images
      - `push_image`: Handles image pushing with error handling
    - Features:
      - Support for multiple registry types (Docker Hub, AWS ECR)
      - Context management with load balancing (round-robin/random)
      - Comprehensive error handling and logging
      - Lock-based login caching
      - Base image support
      - Temporary image tagging support
    - Added proper error handling and logging

## Current Structure

```
.
├── lib/
│   ├── notify.sh       # Notification module
│   ├── system.sh       # System maintenance module
│   ├── common.sh       # Common utilities and logging module
│   ├── analysis.sh     # Code analysis and quality checks module
│   ├── kubernetes.sh   # Kubernetes management module
│   ├── deployment.sh   # Deployment operations module
│   ├── test.sh         # Testing framework module
│   ├── docker.sh       # Docker operations module
│   └── repo.sh         # Repository and VCS management module
├── docs/
│   ├── notify.md       # Notification module documentation
│   └── refactoring.md  # This document
└── deploy.sh           # Main deployment script
```

## Identified Modules for Refactoring

Based on the current codebase analysis, these are the next potential modules to extract:

1. Environment Management
   - Environment variable handling
   - Configuration loading
   - Suggested module: `lib/config.sh`

## Refactoring Guidelines

1. Module Independence
   - Each module should be self-contained
   - Minimize dependencies between modules
   - Clear and well-defined interfaces

2. Documentation Requirements
   - Each module must have its own documentation
   - Document all public functions
   - Include usage examples
   - Document dependencies and requirements

3. Testing Strategy
   - Add test cases for new modules
   - Ensure backwards compatibility
   - Verify integration points

4. Global Variable Standards
   - Use `G` associative array for global configurations
   - Implement clear namespace prefixes:
     ```bash
     # Core program variables
     G[core_name]="$(basename "${BASH_SOURCE[0]}")"
     G[core_path]="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
     G[core_lib_path]="${G[core_path]}/lib"
     G[core_data_path]="${G[core_path]}/data"
     G[core_log_file]="${G[core_data_path]}/${G[core_name]}.log"
     G[core_conf_file]="${G[core_data_path]}/deploy.json"
     G[core_env_file]="${G[core_data_path]}/deploy.env"

     # Module-specific variables
     # kubernetes.sh
     G[k8s_config]="${G[core_data_path]}/k8s/config"
     G[k8s_namespace]="default"

     # docker.sh
     G[docker_file]="${G[core_path]}/Dockerfile"
     G[docker_context]="${G[core_path]}"

     # deployment.sh
     G[deploy_target]="production"
     G[deploy_log_path]="${G[core_data_path]}/deploy/logs"
     ```

   - Follow naming conventions:
     - `*_path` or `*_dir` for directory paths
     - `*_file` for single files, `*_files` for file collections
     - `*_config` or `*_conf` for configurations
     - `*_log` for log files, `*_logs` for log directories

   - Module documentation requirements:
     ```bash
     # Example module header (kubernetes.sh)
     #
     # Uses following G variables:
     # - G[k8s_config]      - K8s configuration file path
     # - G[k8s_namespace]   - K8s namespace
     # - G[k8s_deploy_path] - K8s deployment directory
     #
     # Depends on core variables:
     # - G[core_data_path]  - Core data directory
     ```

   - Benefits:
     - Clear namespace separation
     - Avoid naming conflicts
     - Easy to understand variable ownership
     - Maintainable and documentable
     - Reasonable brevity while maintaining clarity

## Next Steps

1. Testing Enhancement
   - Add unit tests for each module
   - Create test cases for core functionalities
   - Implement continuous integration testing
   - Suggested directory: `lib/tests/`

2. Documentation Completion
   - Create dedicated documentation for each module
   - Add function interface documentation
   - Include usage examples for each module
   - Suggested path: `docs/<module_name>.md`

3. Code Sharing Improvement
   - Create example projects using the modules
   - Add code snippets for common use cases
   - Document module integration patterns
   - Suggested directory: `examples/`

## Progress Tracking

- [x] Version Control System modularization
- [x] Notification system modularization
- [x] System maintenance modularization (including certificate management)
- [x] Common utilities modularization
- [x] Code analysis modularization
- [x] Kubernetes management modularization
- [x] Deployment operations modularization
- [x] Testing framework modularization
- [x] Docker operations modularization
- [x] Repository management modularization
- [x] Configuration management modularization
- [ ] Unit tests implementation
- [ ] Module documentation completion
- [ ] Usage examples creation

## Documentation Status

Current documentation coverage:
- ✅ Notification module (`docs/notify.md`)
- ❌ System maintenance module (including certificate management)
- ❌ Common utilities module
- ❌ Code analysis module
- ❌ Kubernetes management module
- ❌ Deployment operations module
- ❌ Testing framework module
- ❌ Docker operations module
- ❌ Repository and VCS management module
- ❌ Configuration management module

## Container Build Solutions

### 1. Cloud Native Buildpacks
- Description:
  - Developed by Heroku and Google
  - Automatically detects project language and generates optimized container images
  - Supports multiple programming languages
  - No Dockerfile required
- Usage:
  ```bash
  pack build myapp --builder gcr.io/buildpacks/builder:v1
  ```
- Benefits:
  - No need to maintain Dockerfiles
  - Automatic optimization
  - Security patches automatically applied
  - Best practices built-in

### 2. Language-Specific Solutions

#### Jib (Java)
- Description:
  - Developed by Google
  - Specifically designed for Java applications
  - Builds containers from Maven/Gradle directly
- Usage:
  ```bash
  ./gradlew jib
  ```
- Benefits:
  - No Docker daemon required
  - Optimized for Java applications
  - Reproducible builds

#### Source-To-Image (S2I)
- Description:
  - Core technology of Red Hat OpenShift
  - Builds container images directly from source code
  - Provides builder images for various languages
- Usage:
  ```bash
  s2i build . registry.access.redhat.com/ubi8/python-38 myapp
  ```
- Benefits:
  - Standardized build process
  - Security focused
  - Enterprise ready

#### Paketo Buildpacks
- Description:
  - Cloud Foundry Foundation project
  - Modular buildpacks system
  - Multi-language support
- Usage:
  ```bash
  pack build myapp --builder paketobuildpacks/builder:base
  ```
- Benefits:
  - Modular design
  - Active community
  - Regular updates

### 3. Custom Implementation Approaches

#### Base Image Strategy
```bash
# Base images for different languages
declare -A BASE_IMAGES=(
    ["java"]="eclipse-temurin:17-jre-alpine"
    ["python"]="python:3.11-slim"
    ["node"]="node:18-alpine"
    ["go"]="golang:1.20-alpine"
)
```

#### Multi-Stage Build Templates
```dockerfile
# Java Example
FROM maven:3.8-eclipse-temurin-17 AS builder
WORKDIR /build
COPY . .
RUN mvn clean package -DskipTests

FROM eclipse-temurin:17-jre-alpine
COPY --from=builder /build/target/*.jar app.jar
CMD ["java", "-jar", "app.jar"]
```

### 4. Implementation Recommendations

1. Primary Approach: Cloud Native Buildpacks
   - Use for standard applications
   - Minimal configuration required
   - Automatic updates and security patches

2. Custom Dockerfile Generation
   - Use for specialized requirements
   - Implement multi-stage builds
   - Follow security best practices
   - Maintain base image updates

3. Hybrid Approach
   - Simple projects: Buildpacks
   - Complex projects: Custom Dockerfiles
   - Specialized needs: Language-specific tools

### 5. Integration Example

```bash
repo_language_detect_and_build() {
    local target_dir="${1:-.}"
    local lang_type

    # Detect language
    lang_type=$(repo_language_detect)

    # Select appropriate builder
    case "${lang_type%%:*}" in
        java)
            builder="gcr.io/buildpacks/builder:java"
            ;;
        python)
            builder="gcr.io/buildpacks/builder:python"
            ;;
        node)
            builder="gcr.io/buildpacks/builder:nodejs"
            ;;
        go)
            builder="gcr.io/buildpacks/builder:go"
            ;;
        *)
            builder="gcr.io/buildpacks/builder:base"
            ;;
    esac

    # Build using buildpack
    pack build "${ENV_DOCKER_REGISTRY}:${G_IMAGE_TAG}" \
        --builder "$builder" \
        --path "$target_dir"
}
```

### 6. Future Considerations

1. Monitoring and Metrics
   - Build time tracking
   - Image size monitoring
   - Build success rate tracking

2. Security Enhancements
   - Vulnerability scanning integration
   - Base image updates automation
   - Security policy enforcement

3. Performance Optimization
   - Build cache management
   - Layer optimization
   - Build parallelization

4. Developer Experience
   - Local development support
   - Debug capabilities
   - Fast feedback loops