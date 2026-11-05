# Official Solution Guide: WordPress Sidecar Logging Pattern

## Exam Strategy & High-Speed Workflow

In the CKA exam, multi-container logging/sidecar patterns appear frequently under **Workloads & Scheduling**. The goal is typically to share a filesystem between a primary application container and a logging/adapter sidecar using an `emptyDir` volume.

Estimated completion time: **2-3 minutes**.

---

### Step 1: Export or Edit the Existing Deployment

You can directly edit the running deployment with `kubectl edit` or export the YAML:

```bash
kubectl get deployment wordpress -o yaml > /tmp/wordpress.yaml
```

---

### Step 2: Modify the Deployment Specification

In `/tmp/wordpress.yaml` (or via `kubectl edit deployment wordpress`), perform two updates:

1. **Add the shared volume** to `spec.template.spec.volumes`:
   ```yaml
         volumes:
         - name: log-vol
           emptyDir: {}
   ```

2. **Mount the volume to the existing main container** under `spec.template.spec.containers[0]`:
   ```yaml
           volumeMounts:
           - name: log-vol
             mountPath: /var/log
   ```

3. **Add the new sidecar container** under `spec.template.spec.containers`:
   ```yaml
         - name: sidecar
           image: busybox:stable
           command: ["/bin/sh", "-c", "tail -f /var/log/wordpress.log"]
           volumeMounts:
           - name: log-vol
             mountPath: /var/log
   ```

#### Complete Pod Template Section (`spec.template.spec`):

```yaml
    spec:
      volumes:
      - name: log-vol
        emptyDir: {}
      containers:
      - name: wordpress
        image: busybox:stable
        command:
        - /bin/sh
        - -c
        - |
          mkdir -p /var/log
          touch /var/log/wordpress.log
          COUNTER=1
          while true; do
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [NOTICE] WordPress event #$COUNTER: GET /wp-admin 200 OK" >> /var/log/wordpress.log
            COUNTER=$((COUNTER + 1))
            sleep 3
          done
        volumeMounts:
        - name: log-vol
          mountPath: /var/log
      - name: sidecar
        image: busybox:stable
        command: ["/bin/sh", "-c", "tail -f /var/log/wordpress.log"]
        volumeMounts:
        - name: log-vol
          mountPath: /var/log
```

---

### Step 3: Apply the Modified Manifest

```bash
kubectl apply -f /tmp/wordpress.yaml
```

---

### Step 4: Verification

1. **Verify rollout completion:**
   ```bash
   kubectl rollout status deployment/wordpress
   ```

2. **Verify both containers are running (`2/2`):**
   ```bash
   kubectl get pods -l app=wordpress
   ```
   Output:
   ```text
   NAME                         READY   STATUS    RESTARTS   AGE
   wordpress-579c878f78-q7z6k   2/2     Running   0          25s
   ```

3. **Verify log streaming from the sidecar container:**
   ```bash
   kubectl logs deployment/wordpress -c sidecar
   ```
   You should see live WordPress log entries streaming on stdout.

---

## Common CKA Pitfalls

1. **Mounting the volume to only one container:**
   If the volume is only mounted on the sidecar and not on the main container (or vice-versa), they will not share `/var/log`. The sidecar will immediately error with `tail: can't open '/var/log/wordpress.log': No such file or directory` and enter `CrashLoopBackOff`.
2. **Volume name mismatch:**
   The `name` in `volumeMounts` must match the `name` defined under `volumes`.
3. **Command syntax format:**
   Ensure the command array correctly passes shell execution flags:
   `["/bin/sh", "-c", "tail -f /var/log/wordpress.log"]`.
4. **Indentation:**
   Ensure `volumes` is aligned at `spec.template.spec.volumes` (sibling to `containers`), not inside `spec.template.spec.containers`.
