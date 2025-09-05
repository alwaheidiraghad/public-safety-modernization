;; Community Policing Contract
;; System for building community trust through transparent engagement and accountability

;; Error constants
(define-constant ERR_UNAUTHORIZED (err u2001))
(define-constant ERR_INTERACTION_NOT_FOUND (err u2002))
(define-constant ERR_PROGRAM_NOT_FOUND (err u2003))
(define-constant ERR_INVALID_RATING (err u2004))
(define-constant ERR_ALREADY_RATED (err u2005))
(define-constant ERR_INVALID_INPUT (err u2006))
(define-constant ERR_PROGRAM_NOT_ACTIVE (err u2007))

;; Interaction type constants
(define-constant INTERACTION_PATROL u1)
(define-constant INTERACTION_COMMUNITY_EVENT u2)
(define-constant INTERACTION_COMPLAINT_RESOLUTION u3)
(define-constant INTERACTION_EDUCATION u4)
(define-constant INTERACTION_ASSISTANCE u5)

;; Program status constants
(define-constant PROGRAM_ACTIVE u1)
(define-constant PROGRAM_PAUSED u2)
(define-constant PROGRAM_COMPLETED u3)

;; Rating scale constants
(define-constant RATING_MIN u1)
(define-constant RATING_MAX u5)

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var interaction-counter uint u0)
(define-data-var program-counter uint u0)
(define-data-var total-trust-score uint u0)
(define-data-var total-interactions uint u0)

;; Data maps
(define-map community-interactions uint {
    officer: principal,
    community-member: principal,
    interaction-type: uint,
    description: (string-ascii 500),
    location: (string-ascii 200),
    timestamp: uint,
    community-rating: (optional uint),
    officer-notes: (optional (string-ascii 300)),
    follow-up-required: bool
})

(define-map community-programs uint {
    program-name: (string-ascii 100),
    description: (string-ascii 500),
    coordinator: principal,
    start-date: uint,
    end-date: (optional uint),
    status: uint,
    participants: uint,
    budget-allocated: uint,
    community-feedback: (list 10 {
        member: principal,
        rating: uint,
        comment: (string-ascii 300)
    })
})

(define-map officer-profiles principal {
    badge-number: (string-ascii 20),
    name: (string-ascii 50),
    precinct: (string-ascii 30),
    specializations: (list 5 (string-ascii 30)),
    total-interactions: uint,
    average-rating: uint,
    community-endorsements: uint
})

(define-map community-members principal {
    interactions-participated: uint,
    programs-joined: uint,
    feedback-provided: uint,
    trust-contributions: uint
})

(define-map authorized-officers principal bool)
(define-map interaction-ratings (tuple (interaction-id uint) (rater principal)) uint)

(define-map accountability-reports uint {
    reporter: principal,
    subject-officer: principal,
    incident-description: (string-ascii 500),
    report-timestamp: uint,
    status: (string-ascii 20),
    investigation-notes: (optional (string-ascii 500)),
    resolution: (optional (string-ascii 300))
})

(define-data-var report-counter uint u0)

;; Private functions

(define-private (is-authorized-officer (caller principal))
    (or 
        (is-eq caller (var-get contract-owner))
        (default-to false (map-get? authorized-officers caller))
    )
)

(define-private (is-valid-interaction-type (interaction-type uint))
    (and 
        (>= interaction-type INTERACTION_PATROL)
        (<= interaction-type INTERACTION_ASSISTANCE)
    )
)

(define-private (is-valid-rating (rating uint))
    (and 
        (>= rating RATING_MIN)
        (<= rating RATING_MAX)
    )
)

(define-private (update-trust-metrics (rating uint))
    (let (
        (current-total (var-get total-trust-score))
        (current-count (var-get total-interactions))
        (new-total (+ current-total rating))
        (new-count (+ current-count u1))
    )
        (var-set total-trust-score new-total)
        (var-set total-interactions new-count)
        (ok true)
    )
)

(define-private (calculate-officer-rating (officer principal) (new-rating uint))
    (let (
        (profile (unwrap-panic (map-get? officer-profiles officer)))
        (current-interactions (get total-interactions profile))
        (current-avg (get average-rating profile))
        (total-points (* current-interactions current-avg))
        (new-total-points (+ total-points new-rating))
        (new-interaction-count (+ current-interactions u1))
        (new-average (/ new-total-points new-interaction-count))
    )
        (map-set officer-profiles officer 
            (merge profile {
                total-interactions: new-interaction-count,
                average-rating: new-average
            })
        )
        (ok new-average)
    )
)

;; Public functions

;; Initialize contract
(define-public (initialize)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (map-set authorized-officers tx-sender true)
        (ok true)
    )
)

;; Add authorized officer
(define-public (add-officer (officer principal) (badge-number (string-ascii 20)) (name (string-ascii 50)) (precinct (string-ascii 30)))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (asserts! (> (len badge-number) u0) ERR_INVALID_INPUT)
        (asserts! (> (len name) u0) ERR_INVALID_INPUT)
        
        (map-set authorized-officers officer true)
        (map-set officer-profiles officer {
            badge-number: badge-number,
            name: name,
            precinct: precinct,
            specializations: (list),
            total-interactions: u0,
            average-rating: u0,
            community-endorsements: u0
        })
        
        (print {
            event: "officer-added",
            officer: officer,
            badge-number: badge-number,
            precinct: precinct
        })
        
        (ok true)
    )
)

;; Record community interaction
(define-public (record-interaction 
    (community-member principal)
    (interaction-type uint)
    (description (string-ascii 500))
    (location (string-ascii 200))
    (officer-notes (optional (string-ascii 300)))
    (follow-up-required bool)
)
    (let (
        (interaction-id (+ (var-get interaction-counter) u1))
    )
        (asserts! (is-authorized-officer tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-valid-interaction-type interaction-type) ERR_INVALID_INPUT)
        (asserts! (> (len description) u0) ERR_INVALID_INPUT)
        (asserts! (> (len location) u0) ERR_INVALID_INPUT)
        
        (map-set community-interactions interaction-id {
            officer: tx-sender,
            community-member: community-member,
            interaction-type: interaction-type,
            description: description,
            location: location,
            timestamp: stacks-block-height,
            community-rating: none,
            officer-notes: officer-notes,
            follow-up-required: follow-up-required
        })
        
        ;; Update community member stats
        (let (
            (member-stats (default-to {
                interactions-participated: u0,
                programs-joined: u0,
                feedback-provided: u0,
                trust-contributions: u0
            } (map-get? community-members community-member)))
        )
            (map-set community-members community-member 
                (merge member-stats {
                    interactions-participated: (+ (get interactions-participated member-stats) u1)
                })
            )
        )
        
        (var-set interaction-counter interaction-id)
        
        (print {
            event: "interaction-recorded",
            interaction-id: interaction-id,
            officer: tx-sender,
            community-member: community-member,
            interaction-type: interaction-type
        })
        
        (ok interaction-id)
    )
)

;; Community member rates an interaction
(define-public (rate-interaction (interaction-id uint) (rating uint) (feedback (optional (string-ascii 300))))
    (let (
        (interaction (unwrap! (map-get? community-interactions interaction-id) ERR_INTERACTION_NOT_FOUND))
        (rating-key (tuple (interaction-id interaction-id) (rater tx-sender)))
    )
        (asserts! (is-eq tx-sender (get community-member interaction)) ERR_UNAUTHORIZED)
        (asserts! (is-valid-rating rating) ERR_INVALID_RATING)
        (asserts! (is-none (map-get? interaction-ratings rating-key)) ERR_ALREADY_RATED)
        
        ;; Record the rating
        (map-set interaction-ratings rating-key rating)
        
        ;; Update interaction with rating
        (map-set community-interactions interaction-id 
            (merge interaction {
                community-rating: (some rating)
            })
        )
        
        ;; Update officer's average rating
        (unwrap-panic (calculate-officer-rating (get officer interaction) rating))
        
        ;; Update trust metrics
        (unwrap-panic (update-trust-metrics rating))
        
        ;; Update community member stats
        (let (
            (member-stats (default-to {
                interactions-participated: u0,
                programs-joined: u0,
                feedback-provided: u0,
                trust-contributions: u0
            } (map-get? community-members tx-sender)))
        )
            (map-set community-members tx-sender 
                (merge member-stats {
                    feedback-provided: (+ (get feedback-provided member-stats) u1),
                    trust-contributions: (+ (get trust-contributions member-stats) rating)
                })
            )
        )
        
        (print {
            event: "interaction-rated",
            interaction-id: interaction-id,
            rating: rating,
            rater: tx-sender
        })
        
        (ok true)
    )
)

;; Create community program
(define-public (create-program 
    (program-name (string-ascii 100))
    (description (string-ascii 500))
    (end-date (optional uint))
    (budget-allocated uint)
)
    (let (
        (program-id (+ (var-get program-counter) u1))
    )
        (asserts! (is-authorized-officer tx-sender) ERR_UNAUTHORIZED)
        (asserts! (> (len program-name) u0) ERR_INVALID_INPUT)
        (asserts! (> (len description) u0) ERR_INVALID_INPUT)
        
        (map-set community-programs program-id {
            program-name: program-name,
            description: description,
            coordinator: tx-sender,
            start-date: stacks-block-height,
            end-date: end-date,
            status: PROGRAM_ACTIVE,
            participants: u0,
            budget-allocated: budget-allocated,
            community-feedback: (list)
        })
        
        (var-set program-counter program-id)
        
        (print {
            event: "program-created",
            program-id: program-id,
            program-name: program-name,
            coordinator: tx-sender
        })
        
        (ok program-id)
    )
)

;; Join community program
(define-public (join-program (program-id uint))
    (let (
        (program (unwrap! (map-get? community-programs program-id) ERR_PROGRAM_NOT_FOUND))
    )
        (asserts! (is-eq (get status program) PROGRAM_ACTIVE) ERR_PROGRAM_NOT_ACTIVE)
        
        (map-set community-programs program-id 
            (merge program {
                participants: (+ (get participants program) u1)
            })
        )
        
        ;; Update community member stats
        (let (
            (member-stats (default-to {
                interactions-participated: u0,
                programs-joined: u0,
                feedback-provided: u0,
                trust-contributions: u0
            } (map-get? community-members tx-sender)))
        )
            (map-set community-members tx-sender 
                (merge member-stats {
                    programs-joined: (+ (get programs-joined member-stats) u1)
                })
            )
        )
        
        (print {
            event: "program-joined",
            program-id: program-id,
            participant: tx-sender
        })
        
        (ok true)
    )
)

;; Submit accountability report
(define-public (submit-accountability-report 
    (subject-officer principal)
    (incident-description (string-ascii 500))
)
    (let (
        (report-id (+ (var-get report-counter) u1))
    )
        (asserts! (> (len incident-description) u0) ERR_INVALID_INPUT)
        
        (map-set accountability-reports report-id {
            reporter: tx-sender,
            subject-officer: subject-officer,
            incident-description: incident-description,
            report-timestamp: stacks-block-height,
            status: "under-review",
            investigation-notes: none,
            resolution: none
        })
        
        (var-set report-counter report-id)
        
        (print {
            event: "accountability-report-submitted",
            report-id: report-id,
            reporter: tx-sender,
            subject-officer: subject-officer
        })
        
        (ok report-id)
    )
)

;; Update accountability report (officers only)
(define-public (update-accountability-report 
    (report-id uint)
    (status (string-ascii 20))
    (investigation-notes (optional (string-ascii 500)))
    (resolution (optional (string-ascii 300)))
)
    (let (
        (report (unwrap! (map-get? accountability-reports report-id) ERR_INTERACTION_NOT_FOUND))
    )
        (asserts! (is-authorized-officer tx-sender) ERR_UNAUTHORIZED)
        
        (map-set accountability-reports report-id 
            (merge report {
                status: status,
                investigation-notes: investigation-notes,
                resolution: resolution
            })
        )
        
        (print {
            event: "accountability-report-updated",
            report-id: report-id,
            status: status,
            updated-by: tx-sender
        })
        
        (ok true)
    )
)

;; Read-only functions

(define-read-only (get-interaction (interaction-id uint))
    (map-get? community-interactions interaction-id)
)

(define-read-only (get-program (program-id uint))
    (map-get? community-programs program-id)
)

(define-read-only (get-officer-profile (officer principal))
    (map-get? officer-profiles officer)
)

(define-read-only (get-community-member-stats (member principal))
    (map-get? community-members member)
)

(define-read-only (get-accountability-report (report-id uint))
    (map-get? accountability-reports report-id)
)

(define-read-only (get-overall-trust-score)
    (if (> (var-get total-interactions) u0)
        (/ (var-get total-trust-score) (var-get total-interactions))
        u0
    )
)

(define-read-only (get-interaction-count)
    (var-get interaction-counter)
)

(define-read-only (get-program-count)
    (var-get program-counter)
)

(define-read-only (get-report-count)
    (var-get report-counter)
)

(define-read-only (is-officer-authorized (officer principal))
    (default-to false (map-get? authorized-officers officer))
)
