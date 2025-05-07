;; home-iot-logger
;; 
;; This contract provides a secure, immutable logging system for home IoT devices.
;; It allows homeowners to register their NestNode system, add authorized devices,
;; and record cryptographic proofs of device activities without storing sensitive data on-chain.
;; The contract serves as a tamper-proof record for verification and dispute resolution.

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NEST-NODE-ALREADY-REGISTERED (err u101))
(define-constant ERR-NEST-NODE-NOT-REGISTERED (err u102))
(define-constant ERR-DEVICE-ALREADY-REGISTERED (err u103))
(define-constant ERR-DEVICE-NOT-REGISTERED (err u104))
(define-constant ERR-INVALID-DEVICE-ACTION (err u105))
(define-constant ERR-ATTESTATION-EXISTS (err u106))

;; Data space definitions

;; Maps each home's NestNode to its owner's principal
(define-map nest-nodes
  principal  ;; owner
  {
    nest-node-id: (string-ascii 64),
    registration-time: uint
  }
)

;; Stores information about each registered device
(define-map devices
  {
    owner: principal,
    device-id: (string-ascii 64)
  }
  {
    device-name: (string-ascii 64),
    device-type: (string-ascii 32),
    registration-time: uint
  }
)

;; Stores activity attestations (hashes) for each device
(define-map activity-logs
  {
    owner: principal,
    device-id: (string-ascii 64),
    timestamp: uint
  }
  {
    action-hash: (buff 32),    ;; Hash of the device action details
    attestation-hash: (buff 32) ;; Hash combining device-id, timestamp, and action for verification
  }
)

;; Tracks all devices registered to a particular owner for easy enumeration
(define-map owner-devices
  principal  ;; owner
  (list 100 (string-ascii 64))  ;; list of device-ids, max 100 devices
)

;; Private functions

;; Checks if the NestNode is registered to the caller
(define-private (is-nest-node-owner (owner principal))
  (is-some (map-get? nest-nodes owner))
)

;; Adds a device to the owner's device list
(define-private (add-device-to-owner-list (owner principal) (device-id (string-ascii 64)))
  (let (
    (current-devices (default-to (list) (map-get? owner-devices owner)))
  )
    (map-set owner-devices owner (append current-devices device-id))
  )
)

;; Validates if a device is registered to the owner
(define-private (is-device-registered (owner principal) (device-id (string-ascii 64)))
  (is-some (map-get? devices {owner: owner, device-id: device-id}))
)

;; Public functions

;; Registers a new NestNode system for the homeowner
(define-public (register-nest-node (nest-node-id (string-ascii 64)))
  (let (
    (caller tx-sender)
  )
    (asserts! (is-none (map-get? nest-nodes caller)) ERR-NEST-NODE-ALREADY-REGISTERED)
    
    (map-set nest-nodes caller {
      nest-node-id: nest-node-id,
      registration-time: block-height
    })
    
    (ok true)
  )
)

;; Registers a new IoT device to the homeowner's network
(define-public (register-device 
    (device-id (string-ascii 64))
    (device-name (string-ascii 64))
    (device-type (string-ascii 32)))
  (let (
    (caller tx-sender)
  )
    ;; Check that caller has a registered NestNode
    (asserts! (is-nest-node-owner caller) ERR-NEST-NODE-NOT-REGISTERED)
    ;; Check that device isn't already registered
    (asserts! (not (is-device-registered caller device-id)) ERR-DEVICE-ALREADY-REGISTERED)
    
    ;; Register the device
    (map-set devices 
      {owner: caller, device-id: device-id}
      {
        device-name: device-name,
        device-type: device-type,
        registration-time: block-height
      }
    )
    
    ;; Add device to owner's device list
    (add-device-to-owner-list caller device-id)
    
    (ok true)
  )
)

;; Records an activity attestation for a device
(define-public (log-device-activity 
    (device-id (string-ascii 64))
    (timestamp uint)
    (action-hash (buff 32))
    (attestation-hash (buff 32)))
  (let (
    (caller tx-sender)
    (log-key {owner: caller, device-id: device-id, timestamp: timestamp})
  )
    ;; Check that caller has a registered NestNode
    (asserts! (is-nest-node-owner caller) ERR-NEST-NODE-NOT-REGISTERED)
    ;; Check that device is registered
    (asserts! (is-device-registered caller device-id) ERR-DEVICE-NOT-REGISTERED)
    ;; Ensure this exact log doesn't already exist
    (asserts! (is-none (map-get? activity-logs log-key)) ERR-ATTESTATION-EXISTS)
    
    ;; Store the activity attestation
    (map-set activity-logs log-key
      {
        action-hash: action-hash,
        attestation-hash: attestation-hash
      }
    )
    
    (ok true)
  )
)

;; Read-only functions

;; Gets details of a registered NestNode
(define-read-only (get-nest-node-info (owner principal))
  (map-get? nest-nodes owner)
)

;; Gets details of a registered device
(define-read-only (get-device-info (owner principal) (device-id (string-ascii 64)))
  (map-get? devices {owner: owner, device-id: device-id})
)

;; Gets all devices registered to an owner
(define-read-only (get-owner-devices (owner principal))
  (default-to (list) (map-get? owner-devices owner))
)

;; Retrieves a specific activity log
(define-read-only (get-activity-log (owner principal) (device-id (string-ascii 64)) (timestamp uint))
  (map-get? activity-logs {owner: owner, device-id: device-id, timestamp: timestamp})
)

;; Verifies if a provided attestation matches the stored one
(define-read-only (verify-activity-attestation 
    (owner principal)
    (device-id (string-ascii 64))
    (timestamp uint)
    (provided-attestation-hash (buff 32)))
  (let (
    (log-entry (map-get? activity-logs {owner: owner, device-id: device-id, timestamp: timestamp}))
  )
    (and
      (is-some log-entry)
      (is-eq provided-attestation-hash (get attestation-hash (unwrap-panic log-entry)))
    )
  )
)

;; Checks if a device was active at a specific time by verifying existence of a log
(define-read-only (was-device-active (owner principal) (device-id (string-ascii 64)) (timestamp uint))
  (is-some (map-get? activity-logs {owner: owner, device-id: device-id, timestamp: timestamp}))
)