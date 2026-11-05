# Task: Re-establish MariaDB Workload with Persistent Storage

**Context:**
Ensure you are operating in the `default` cluster context.

**Target Namespace:**
`mariadb`

**Scenario:**
An operator inadvertently deleted the MariaDB Deployment and its associated PersistentVolumeClaim in the `mariadb` namespace. The backing PersistentVolume containing existing database data has been retained and is currently available for reuse (`Available` status). Exactly one PersistentVolume exists in the cluster.

A baseline manifest for the MariaDB Deployment is saved on the control node at `~/mariadb-deploy.yaml`.

**Requirements:**
1. In namespace `mariadb`, create a PersistentVolumeClaim (PVC) named `mariadb` with:
   - Access Mode: `ReadWriteOnce`
   - Requested Storage: `250Mi`
   Ensure the claim successfully binds to the existing PersistentVolume.

2. Modify the MariaDB Deployment manifest located at `~/mariadb-deploy.yaml` so that its Pod template uses the PersistentVolumeClaim `mariadb` created in Step 1 to mount storage onto the existing mount path `/var/lib/mysql`.

3. Apply the updated Deployment manifest to the cluster in namespace `mariadb`.

4. Ensure the MariaDB Deployment is running and stable, with its replica reporting a healthy (`1/1 Ready`) state.
