# Cortex-DC-Web Directory Merge Strategy

## Overview

We have two cortex-dc-web directories that need to be consolidated:
- **Source**: `/Users/henry/cortex-dc-web` (newer - contains testing infrastructure, docs, enhanced configs)
- **Target**: `/Users/henry/Github/Github_desktop/cortex-dc-web` (original - contains hosting/, proper Firebase structure)

## Directory Analysis Summary

### Source Directory (`~/cortex-dc-web`) - NEWER
**Unique Content:**
- `docs/` - Comprehensive documentation (7+ MD files)
- `tests/` - Complete testing infrastructure 
- `jest.config.js` - Enhanced testing configuration
- `package.json.testing` - Testing dependencies
- Enhanced `firebase.json` configuration
- `apps/`, `packages/`, `services/` - Monorepo structure
- `pnpm-workspace.yaml` - Workspace configuration

### Target Directory (`~/Github/Github_desktop/cortex-dc-web`) - ORIGINAL  
**Unique Content:**
- `hosting/` - Main web application code
- `cortex-dc-web-functions/` - Cloud Functions
- `apphosting.yaml`, `apphosting.emulator.yaml` - App hosting configs
- `.github/` - GitHub workflows
- `extensions/` - Firebase extensions
- Git history with proper remote tracking

## Merge Strategy

### Phase 1: Pre-merge Preparation
1. **Backup Target Directory**
2. **Identify Critical Files to Preserve**
3. **Create Merge Mapping**

### Phase 2: Content Migration
1. **Copy Unique Documentation** (`docs/` → `hosting/docs/`)
2. **Migrate Testing Infrastructure** (`tests/` → `tests/`)
3. **Update Configuration Files**
4. **Preserve Git History**

### Phase 3: Configuration Reconciliation
1. **Merge package.json files**
2. **Combine firebase.json configurations**
3. **Update workspace configuration**
4. **Reconcile TypeScript configs**

### Phase 4: Validation and Cleanup
1. **Verify all files are present**
2. **Test Firebase deployment**
3. **Remove duplicate directory**

## File-by-File Merge Plan

### Documentation (Priority: HIGH)
```bash
# Source → Target mapping
~/cortex-dc-web/docs/ → ~/Github/Github_desktop/cortex-dc-web/hosting/docs/
```

**Files to migrate:**
- `docs/frontend-migration-implementation-summary.md`
- `docs/dataconnect-architecture.md`
- `docs/frontend-ui-migration-strategy.md`
- `docs/enterprise-roadmap-enhancement.md`
- `docs/firebase-service-testing-strategy.md`
- `docs/ux-testing-architecture.md`
- `docs/ux-testing-rbac-strategy.md`
- `docs/migration/` (entire directory)

### Testing Infrastructure (Priority: HIGH)
```bash
# Source → Target mapping
~/cortex-dc-web/tests/ → ~/Github/Github_desktop/cortex-dc-web/tests/
~/cortex-dc-web/jest.config.js → ~/Github/Github_desktop/cortex-dc-web/jest.config.js
```

### Configuration Files (Priority: CRITICAL)
```bash
# Merge strategy for each config file:

# firebase.json - MERGE (combine configurations)
# package.json - MERGE (combine dependencies and scripts)
# tsconfig.json - USE SOURCE (enhanced version)
# pnpm-workspace.yaml - COPY SOURCE
```

### Monorepo Structure (Priority: MEDIUM)
```bash
# Create monorepo structure in target:
~/Github/Github_desktop/cortex-dc-web/apps/web/ ← hosting/
~/Github/Github_desktop/cortex-dc-web/packages/ ← packages/
~/Github/Github_desktop/cortex-dc-web/services/ ← services/
```

## Execution Commands

### Step 1: Create Backup
```bash
cd ~/Github/Github_desktop
cp -r cortex-dc-web cortex-dc-web-backup-$(date +%Y%m%d-%H%M%S)
```

### Step 2: Migrate Documentation
```bash
cd ~/Github/Github_desktop/cortex-dc-web
mkdir -p hosting/docs
cp -r ~/cortex-dc-web/docs/* hosting/docs/
```

### Step 3: Migrate Testing Infrastructure  
```bash
cp -r ~/cortex-dc-web/tests/ ./
cp ~/cortex-dc-web/jest.config.js ./
cp ~/cortex-dc-web/package.json.testing ./
```

### Step 4: Create Monorepo Structure
```bash
mkdir -p apps packages services
mv hosting apps/web
cp -r ~/cortex-dc-web/packages/* packages/
cp -r ~/cortex-dc-web/services/* services/
```

### Step 5: Update Configuration Files
```bash
# Merge package.json (manual step required)
# Merge firebase.json (manual step required)
# Copy workspace config
cp ~/cortex-dc-web/pnpm-workspace.yaml ./
cp ~/cortex-dc-web/tsconfig.json ./
```

## Critical Files to Handle Manually

### 1. package.json Merge
- **Source scripts**: testing, workspace management
- **Target scripts**: Firebase deployment, hosting
- **Dependencies**: Merge both sets

### 2. firebase.json Merge  
- **Source**: Enhanced emulator configuration
- **Target**: App hosting configuration
- **Merge**: Combine both configurations

### 3. Git Configuration
- **Preserve**: Target's .git directory (has remote tracking)
- **Add**: Source content as new commits

## Risk Mitigation

### Backup Strategy
1. **Full backup** of target directory before merge
2. **Git stash** any uncommitted changes
3. **Export Firebase data** if needed

### Validation Checklist
- [ ] All documentation files present
- [ ] Testing infrastructure functional
- [ ] Firebase deployment successful
- [ ] All npm scripts working
- [ ] TypeScript compilation successful
- [ ] Emulators start correctly

### Rollback Plan
If merge fails:
1. **Restore from backup**
2. **Reset git to last known good state**
3. **Retry with selective merge approach**

## Post-Merge Tasks

### 1. Update README
- Document new monorepo structure
- Update build and deployment instructions
- Add testing documentation

### 2. Update CI/CD
- Modify GitHub workflows for new structure
- Update deployment scripts
- Test automated builds

### 3. Team Communication
- Notify team of directory structure changes
- Provide new development setup instructions
- Update contribution guidelines

## Success Criteria

### Functional Requirements
- [ ] `firebase deploy` works successfully
- [ ] All tests pass (`npm run test:critical`)
- [ ] Development server starts correctly
- [ ] All documentation is accessible
- [ ] Monorepo commands function properly

### Non-Functional Requirements  
- [ ] No data loss during merge
- [ ] Git history preserved
- [ ] All team members can continue development
- [ ] Performance not degraded
- [ ] All integrations still functional

## Next Steps After Merge

1. **Update external references** to new directory structure
2. **Run comprehensive tests** to validate functionality
3. **Update deployment scripts** if needed
4. **Archive backup directory** after validation
5. **Document lessons learned** for future merges