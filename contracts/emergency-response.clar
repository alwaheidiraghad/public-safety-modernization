;; Emergency Response Contract
;; Comprehensive system for managing emergency incidents, resources, and response coordination

;; Error constants
(define-constant ERR_UNAUTHORIZED (err u1001))
(define-constant ERR_INCIDENT_NOT_FOUND (err u1002))
(define-constant ERR_INVALID_STATUS (err u1003))
(define-constant ERR_RESOURCE_NOT_AVAILABLE (err u1004))
(define-constant ERR_INVALID_PRIORITY (err u1005))
(define-constant ERR_ALREADY_ASSIGNED (err u1006))
(define-constant ERR_INVALID_INPUT (err u1007))

;; Status constants
(define-constant STATUS_REPORTED u1)
(define-constant STATUS_DISPATCHED u2)
(define-constant STATUS_IN_PROGRESS u3)
(define-constant STATUS_RESOLVED u4)
(define-constant STATUS_CLOSED u5)

;; Priority constants
(define-constant PRIORITY_LOW u1)
(define-constant PRIORITY_MEDIUM u2)
(define-constant PRIORITY_HIGH u3)
(define-constant PRIORITY_CRITICAL u4)

;; Resource type constants
(define-constant RESOURCE_POLICE u1)
(define-constant RESOURCE_FIRE u2)
(define-constant RESOURCE_MEDICAL u3)
(define-constant RESOURCE_RESCUE u4)

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var incident-counter uint u0)
(define-data-var resource-counter uint u0)

;; Data maps
(define-map incidents uint {
    reporter: principal,
    incident-type: (string-ascii 50),
    description: (string-ascii 500),
    location: (string-ascii 200),
    priority: uint,
    status: uint,
    created-at: uint,
    updated-at: uint,
    assigned-resources: (list 10 uint),
    response-time: (optional uint)
})

(define-map resources uint {
    resource-type: uint,
    identifier: (string-ascii 50),
    location: (string-ascii 200),
    status: (string-ascii 20),
    assigned-incident: (optional uint),
    capabilities: (list 5 (string-ascii 50))
})

(define-map authorized-dispatchers principal bool)

(define-map incident-logs uint (list 20 {
    timestamp: uint,
    action: (string-ascii 100),
    actor: principal,
    details: (string-ascii 300)
}))

;; Private functions

(define-private (is-authorized-dispatcher (caller principal))
    (or 
        (is-eq caller (var-get contract-owner))
        (default-to false (map-get? authorized-dispatchers caller))
    )
)

(define-private (is-valid-status (status uint))
    (and 
        (>= status STATUS_REPORTED)
        (<= status STATUS_CLOSED)
    )
)

(define-private (is-valid-priority (priority uint))
    (and 
        (>= priority PRIORITY_LOW)
        (<= priority PRIORITY_CRITICAL)
    )
)

(define-private (is-valid-resource-type (resource-type uint))
    (and 
        (>= resource-type RESOURCE_POLICE)
        (<= resource-type RESOURCE_RESCUE)
    )
)

(define-private (add-incident-log (incident-id uint) (action (string-ascii 100)) (details (string-ascii 300)))
    (let (
        (current-logs (default-to (list) (map-get? incident-logs incident-id)))
        (new-log {
            timestamp: stacks-block-height,
            action: action,
            actor: tx-sender,
            details: details
        })
    )
        (map-set incident-logs incident-id 
            (unwrap-panic (as-max-len? (append current-logs new-log) u20))
        )
        (ok true)
    )
)

;; Public functions

;; Initialize contract with owner
(define-public (initialize)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (map-set authorized-dispatchers tx-sender true)
        (ok true)
    )
)

;; Add authorized dispatcher
(define-public (add-dispatcher (dispatcher principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (map-set authorized-dispatchers dispatcher true)
        (ok true)
    )
)

;; Create new incident
(define-public (create-incident 
    (incident-type (string-ascii 50))
    (description (string-ascii 500))
    (location (string-ascii 200))
    (priority uint)
)
    (let (
        (incident-id (+ (var-get incident-counter) u1))
    )
        (asserts! (> (len incident-type) u0) ERR_INVALID_INPUT)
        (asserts! (> (len description) u0) ERR_INVALID_INPUT)
        (asserts! (> (len location) u0) ERR_INVALID_INPUT)
        (asserts! (is-valid-priority priority) ERR_INVALID_PRIORITY)
        
        (map-set incidents incident-id {
            reporter: tx-sender,
            incident-type: incident-type,
            description: description,
            location: location,
            priority: priority,
            status: STATUS_REPORTED,
            created-at: stacks-block-height,
            updated-at: stacks-block-height,
            assigned-resources: (list),
            response-time: none
        })
        
        (var-set incident-counter incident-id)
        (unwrap-panic (add-incident-log incident-id "CREATED" "Incident reported"))
        
        (print {
            event: "incident-created",
            incident-id: incident-id,
            reporter: tx-sender,
            priority: priority
        })
        
        (ok incident-id)
    )
)

;; Update incident status
(define-public (update-incident-status (incident-id uint) (new-status uint))
    (let (
        (incident (unwrap! (map-get? incidents incident-id) ERR_INCIDENT_NOT_FOUND))
    )
        (asserts! (is-authorized-dispatcher tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-valid-status new-status) ERR_INVALID_STATUS)
        
        (map-set incidents incident-id 
            (merge incident {
                status: new-status,
                updated-at: stacks-block-height,
                response-time: (if (is-eq new-status STATUS_DISPATCHED)
                    (some (- stacks-block-height (get created-at incident)))
                    (get response-time incident)
                )
            })
        )
        
        (unwrap-panic (add-incident-log incident-id "STATUS_UPDATE" 
            "Status updated"))
        
        (print {
            event: "incident-status-updated",
            incident-id: incident-id,
            new-status: new-status,
            updated-by: tx-sender
        })
        
        (ok true)
    )
)

;; Register new resource
(define-public (register-resource 
    (resource-type uint)
    (identifier (string-ascii 50))
    (location (string-ascii 200))
    (capabilities (list 5 (string-ascii 50)))
)
    (let (
        (resource-id (+ (var-get resource-counter) u1))
    )
        (asserts! (is-authorized-dispatcher tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-valid-resource-type resource-type) ERR_INVALID_INPUT)
        (asserts! (> (len identifier) u0) ERR_INVALID_INPUT)
        (asserts! (> (len location) u0) ERR_INVALID_INPUT)
        
        (map-set resources resource-id {
            resource-type: resource-type,
            identifier: identifier,
            location: location,
            status: "available",
            assigned-incident: none,
            capabilities: capabilities
        })
        
        (var-set resource-counter resource-id)
        
        (print {
            event: "resource-registered",
            resource-id: resource-id,
            resource-type: resource-type,
            identifier: identifier
        })
        
        (ok resource-id)
    )
)

;; Assign resource to incident
(define-public (assign-resource (incident-id uint) (resource-id uint))
    (let (
        (incident (unwrap! (map-get? incidents incident-id) ERR_INCIDENT_NOT_FOUND))
        (resource (unwrap! (map-get? resources resource-id) ERR_RESOURCE_NOT_AVAILABLE))
        (current-resources (get assigned-resources incident))
    )
        (asserts! (is-authorized-dispatcher tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status resource) "available") ERR_RESOURCE_NOT_AVAILABLE)
        (asserts! (is-none (index-of current-resources resource-id)) ERR_ALREADY_ASSIGNED)
        
        ;; Update incident with new resource
        (map-set incidents incident-id 
            (merge incident {
                assigned-resources: (unwrap-panic (as-max-len? (append current-resources resource-id) u10)),
                updated-at: stacks-block-height
            })
        )
        
        ;; Update resource status
        (map-set resources resource-id 
            (merge resource {
                status: "assigned",
                assigned-incident: (some incident-id)
            })
        )
        
        (unwrap-panic (add-incident-log incident-id "RESOURCE_ASSIGNED" 
            (concat "Resource " (get identifier resource))))
        
        (print {
            event: "resource-assigned",
            incident-id: incident-id,
            resource-id: resource-id,
            assigned-by: tx-sender
        })
        
        (ok true)
    )
)

;; Release resource from incident
(define-public (release-resource (resource-id uint))
    (let (
        (resource (unwrap! (map-get? resources resource-id) ERR_RESOURCE_NOT_AVAILABLE))
        (incident-id-opt (get assigned-incident resource))
    )
        (asserts! (is-authorized-dispatcher tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-some incident-id-opt) ERR_RESOURCE_NOT_AVAILABLE)
        
        (let (
            (incident-id (unwrap-panic incident-id-opt))
            (incident (unwrap! (map-get? incidents incident-id) ERR_INCIDENT_NOT_FOUND))
        )
            ;; Update resource status
            (map-set resources resource-id 
                (merge resource {
                    status: "available",
                    assigned-incident: none
                })
            )
            
            ;; Remove resource from incident - simplified approach
            (map-set incidents incident-id 
                (merge incident {
                    assigned-resources: (list),
                    updated-at: stacks-block-height
                })
            )
            
            (unwrap-panic (add-incident-log incident-id "RESOURCE_RELEASED" 
                (concat "Resource " (get identifier resource))))
            
            (print {
                event: "resource-released",
                incident-id: incident-id,
                resource-id: resource-id,
                released-by: tx-sender
            })
            
            (ok true)
        )
    )
)

;; Read-only functions

(define-read-only (get-incident (incident-id uint))
    (map-get? incidents incident-id)
)

(define-read-only (get-resource (resource-id uint))
    (map-get? resources resource-id)
)

(define-read-only (get-incident-logs (incident-id uint))
    (map-get? incident-logs incident-id)
)

(define-read-only (get-incident-count)
    (var-get incident-counter)
)

(define-read-only (get-resource-count)
    (var-get resource-counter)
)

(define-read-only (is-dispatcher (principal principal))
    (default-to false (map-get? authorized-dispatchers principal))
)
