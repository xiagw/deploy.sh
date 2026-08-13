# Code Refactoring Documentation

This document tracks the progress and steps of our code modularization efforts for the deployment script system.

## Completed Refactoring Steps

1. Repository Management (`lib/repo.sh`)
   - Handles repository-specific configuration, file management, and version control operations
   - Functions include:
     - Repository management:
       - `repo_inject_file`: Injects files and configurations into repository
       - `detect_repo_language`: Detects repository programming language
     - Version control operations:
       - `setup_git_repo`: Git repository setup and management
       - `setup_svn_repo`: SVN repository setup and management
       - `get_git_branch`: Branch detection
       - `get_git_commit_sha`: Commit SHA retrieval
       - `get_git_last_commit_message`: Commit message retrieval
   - Features:
     - Centralized repository configuration management
     - Language detection and setup
     - Docker build configuration
     - Environment-specific file handling
     - Support for multiple VCS (Git, SVN)
     - Repository setup and configuration
     - Branch and commit management
     - Comprehensive error handling
   - Added proper error handling and logging
  
2. Notification System (`lib/notify.sh`)
   - Unified notification interface for multiple channels
   - Supports WeChat Work, Telegram, Element, Email, Zoom, and Feishu
   - Functions include:
     - `handle_notify`: Main interface for all channels
     - `notify_wecom`: WeChat Work notifications
     - `notify_telegram`: Telegram notifications
     - `notify_element`: Element notifications
     - `notify_email`: Email notifications
     - `notify_zoom`: Zoom notifications
     - `notify_feishu`: Feishu notifications
   - Added comprehensive documentation in `docs/notify.md`

3. System Maintenance (`lib/system.sh`)
   - Centralized system maintenance and cleanup operations
   - Functions include:
     - `system_clean_disk`: Clean up disk space when usage exceeds threshold (`ENV_DISK_THRESHOLD`, default 80%)
     - `update_nginx_geoip_db`: Nginx GeoIP database updates
     - `system_check`: Check system requirements and install dependencies
     - `system_cert_renew`: Renew SSL certificates with acme.sh
     - `system_install_tools`: Install project-required system tools and dependencies
     - `check_docker_available` / `check_k8s_available` / `check_helm_charts_exist`: Availability probes
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
     - `_msg`: Core logging function with level-based filtering (`note/task/warn/error/stage/anchor/ok`)
     - `_t` / `_msg_lang`: Bilingual (zh/en) message output, CLI `--lang` (`G_MSG_LANG`) > `ENV_LANG` > zh
     - `_install_*`: Tool installation helpers (docker, kubectl, helm, ossutil, aliyun CLI, terraform, ...)
     - `get_oom_score` / `get_github_latest_download`: Common utilities
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
     - `analysis_pmd` / `analysis_checkstyle` / `analysis_spotbugs`: Java analysis
     - `analysis_codeclimate` / `analysis_pylint`: Python/CodeClimate analysis

6. Kubernetes Management (`lib/kubernetes.sh`)
   - Handles Kubernetes cluster operations
   - Functions include:
     - `kube_config_init`: Initialize Kubernetes configuration
     - `kube_setup_terraform`: Setup Kubernetes cluster using Terraform
     - `create_helm_chart`: Creates and configures Helm charts
     - `kube_create_storage_class`: Create CNFS NAS storage class resources
     - `kube_create_pv_pvc`: Create PVC with specified name
     - `build_base_image` / `select_image_tags`: Base image build helpers
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
     - `handle_deploy`: Main deployment orchestration function
     - `detect_deployment_method`: Determines deployment strategy
     - `deploy_to_kubernetes`: Kubernetes deployment with Helm
     - `deploy_via_rsync_ssh`: Rsync+SSH deployment
     - `deploy_to_docker_compose`: Docker Compose deployment over SSH
     - `deploy_aliyun_oss`: Aliyun OSS deployment
     - `deploy_aliyun_functions`: Aliyun Functions deployment
     - `deploy_via_rsync`: Rsync server (rsyncd) deployment
     - `deploy_via_ftp` / `deploy_via_sftp`: FTP / SFTP deployment
     - `copy_docker_image`: Copy image between registries
     - `clean_old_tags`: Clean old registry tags (`ENV_CLEAN_TAGS_DAYS`, default 180)
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
     - `handle_test`: Test stage dispatcher (unit/functional), result in `G_TEST_RESULT`
   - Features:
     - Flexible test script location support
     - Clear success/failure reporting
     - Comprehensive error handling
     - Integration with project-specific and global test scripts
   - Added proper logging and status reporting

9. Build Operations (`lib/build.sh`)
   - Handles Docker/Podman image building for all supported languages
   - Functions include:
     - `docker_login`: Manages Docker registry authentication
     - `build_image` / `build_all`: Builds Docker images
     - `build_java`/`build_node`/`build_python`/`build_go`/`build_php`/`build_ruby`/`build_android`/`build_ios`/`build_docker`: Language-specific builders
     - `generate_bake_file` / `ensure_buildx_builder` / `enable_buildx_mode`: Buildx/Bake orchestration
     - `generate_lang_dockerfile`: Writes `Dockerfile.<lang>` from detected language
     - `detect_repo_language_and_build`: Cloud Native Buildpacks build (`pack build`)
   - Features:
     - Support for multiple registry types (Docker Hub, AWS ECR, Aliyun ACR)
     - Context management for buildx modes
     - Lock-based login caching
     - Base image support
     - Temporary image tagging support
     - Retention control via `ENV_IMAGE_RETAIN` / `-B push|keep|remove`
   - Added proper error handling and logging

10. Configuration Management (`lib/config.sh`)
    - Centralized environment and project configuration management
    - Functions include:
      - `find_project_config`: Locate and create project-specific config (`data/conf/namespace/project-name.json`)
      - `check_project_config_template`: Reject template placeholder values before deployment
      - `config_deploy_init`: Bootstrap data dir, PATH, and deploy.env
      - `config_deploy_setup`: Symlink SSH keys / tool configs into `$HOME`
      - `env_file_set` / `env_file_get` / `env_file_list`: `deploy.sh set/get/env` operations on deploy.env
    - Features:
      - Per-project config separation (no single oversized file)
      - Template placeholder interception covering all deploy methods
      - Environment variable CRUD against deploy.env

11. Code Style Checking (`lib/style.sh`)
    - Centralized code style checks per language
    - Functions include:
      - `style_check`: Style check dispatcher based on detected language
      - `check_php_style` / `check_node_style` / `check_java_style` / `check_go_style` / ...: Language-specific checkers
    - Features:
      - Parallel style checking
      - Detection-based dispatch (go/golang, etc.)

## Current Structure

```
.
├── lib/
│   ├── common.sh       # Common utilities and logging module
│   ├── config.sh       # Configuration management module
│   ├── system.sh       # System maintenance module
│   ├── repo.sh         # Repository and VCS management module
│   ├── test.sh         # Testing framework module
│   ├── analysis.sh     # Code analysis and quality checks module
│   ├── style.sh        # Code style checking module
│   ├── build.sh        # Build and Docker operations module
│   ├── deployment.sh   # Deployment operations module
│   ├── kubernetes.sh   # Kubernetes management module
│   └── notify.sh       # Notification module
├── docs/
│   ├── notify.md       # Notification module documentation
│   ├── architecture.md # Architecture overview
│   ├── code-review.md  # Code audit findings and status
│   └── refactoring.md  # This document
└── deploy.sh           # Main deployment script
```

## Identified Modules for Refactoring

Configuration management has been extracted to `lib/config.sh` (see step 10 above); all remaining modules are already modularized. New functionality should be added to the existing per-domain module.

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
   - Use plain global variables with a `G_*` prefix (no associative `G[...]` array). Current convention, see `AGENTS.md` and the variable comment at the top of `main()` in `deploy.sh`:
     ```bash
     G_NAME="$(basename "${BASH_SOURCE[0]}")"
     G_PATH="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
     G_LIB="${G_PATH}/lib"
     G_DATA="${G_PATH}/data"
     G_ENV="${G_DATA}/deploy.env"
     G_LOG="${G_DATA}/logs/${G_NAME}.log"
     # Module-level globals: G_REPO_DIR, G_NAMESPACE, G_IMAGE_TAG, G_DOCK, ...
     ```
   - Namespace prefixes:
     - `G_*`   : cross-module shared globals
     - `ENV_*` : configuration from deploy.env
     - `arg_*` : command-line arguments
     - `CI_*` / `GITHUB_*` : CI platform injected variables
     - everything else must be `local` within a function
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
     # - G_K8S_CONFIG        - K8s configuration file path
     # - G_K8S_NAMESPACE     - K8s namespace
     # - G_DATA              - Core data directory
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
- [x] Build/Docker operations modularization (`lib/build.sh`)
- [x] Repository management modularization
- [x] Configuration management modularization
- [x] Code style checking modularization
- [ ] Unit tests implementation
- [ ] Module documentation completion
- [ ] Usage examples creation

## Documentation Status

Current documentation coverage:
- ✅ Notification module (`docs/notify.md`)
- ✅ Architecture overview (`docs/architecture.md`)
- ✅ Code audit findings (`docs/code-review.md`)
- ❌ System maintenance module (including certificate management)
- ❌ Common utilities module
- ❌ Code analysis module
- ❌ Kubernetes management module
- ❌ Deployment operations module
- ❌ Testing framework module
- ❌ Build/Docker operations module
- ❌ Repository and VCS management module
- ❌ Configuration management module
- ❌ Code style checking module

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
detect_repo_language_and_build() {
    local target_dir="${1:-.}"
    local lang_type

    # Detect language
    lang_type=$(detect_repo_language)

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
    pack build "${ENV_DOCKER_REGISTRY%/}/${G_IMAGE_NAME}:${G_IMAGE_TAG}" \
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