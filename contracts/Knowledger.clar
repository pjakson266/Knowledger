
;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_PAPER_NOT_FOUND (err u101))
(define-constant ERR_INSUFFICIENT_FUNDS (err u102))
(define-constant ERR_PAPER_ALREADY_EXISTS (err u103))
(define-constant ERR_INVALID_AMOUNT (err u104))
(define-constant ERR_REVIEW_NOT_FOUND (err u105))
(define-constant ERR_ALREADY_REVIEWED (err u106))
(define-constant ERR_PAPER_NOT_SUBMITTED (err u107))
(define-constant ERR_BOUNTY_CLAIMED (err u108))
(define-constant MIN_BOUNTY_AMOUNT u1000000)
(define-constant MIN_REVIEW_REWARD u100000)
(define-constant REVIEW_THRESHOLD u3)

;; data vars
(define-data-var next-paper-id uint u1)
(define-data-var next-review-id uint u1)
(define-data-var platform-fee-rate uint u250)

;; data maps
(define-map papers
  uint
  {
    author: principal,
    title: (string-ascii 256),
    abstract: (string-ascii 1024),
    bounty-amount: uint,
    review-reward: uint,
    submission-block: uint,
    status: (string-ascii 20),
    review-count: uint,
    total-score: uint,
    bounty-claimed: bool
  }
)

(define-map reviews
  uint
  {
    paper-id: uint,
    reviewer: principal,
    score: uint,
    feedback: (string-ascii 512),
    review-block: uint,
    reward-claimed: bool
  }
)

(define-map paper-funders
  { paper-id: uint, funder: principal }
  { amount: uint }
)

(define-map user-reviews
  { paper-id: uint, reviewer: principal }
  { review-id: uint }
)

(define-map author-papers
  { author: principal, paper-index: uint }
  { paper-id: uint }
)

(define-map author-paper-count
  principal
  uint
)

;; public functions
(define-public (create-paper (title (string-ascii 256)) (abstract (string-ascii 1024)) (review-reward uint))
  (let
    (
      (paper-id (var-get next-paper-id))
      (current-count (default-to u0 (map-get? author-paper-count tx-sender)))
    )
    (asserts! (>= review-reward MIN_REVIEW_REWARD) ERR_INVALID_AMOUNT)
    (map-set papers paper-id
      {
        author: tx-sender,
        title: title,
        abstract: abstract,
        bounty-amount: u0,
        review-reward: review-reward,
        submission-block: stacks-block-height,
        status: "draft",
        review-count: u0,
        total-score: u0,
        bounty-claimed: false
      }
    )
    (map-set author-papers { author: tx-sender, paper-index: current-count } { paper-id: paper-id })
    (map-set author-paper-count tx-sender (+ current-count u1))
    (var-set next-paper-id (+ paper-id u1))
    (ok paper-id)
  )
)

(define-public (fund-paper (paper-id uint) (amount uint))
  (let
    (
      (paper (unwrap! (map-get? papers paper-id) ERR_PAPER_NOT_FOUND))
      (current-funding (default-to u0 (get amount (map-get? paper-funders { paper-id: paper-id, funder: tx-sender }))))
    )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set paper-funders { paper-id: paper-id, funder: tx-sender } { amount: (+ current-funding amount) })
    (map-set papers paper-id
      (merge paper { bounty-amount: (+ (get bounty-amount paper) amount) })
    )
    (ok true)
  )
)

(define-public (submit-paper-for-review (paper-id uint))
  (let
    (
      (paper (unwrap! (map-get? papers paper-id) ERR_PAPER_NOT_FOUND))
    )
    (asserts! (is-eq (get author paper) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (>= (get bounty-amount paper) MIN_BOUNTY_AMOUNT) ERR_INSUFFICIENT_FUNDS)
    (map-set papers paper-id
      (merge paper { status: "under-review" })
    )
    (ok true)
  )
)

(define-public (submit-review (paper-id uint) (score uint) (feedback (string-ascii 512)))
  (let
    (
      (paper (unwrap! (map-get? papers paper-id) ERR_PAPER_NOT_FOUND))
      (review-id (var-get next-review-id))
      (existing-review (map-get? user-reviews { paper-id: paper-id, reviewer: tx-sender }))
    )
    (asserts! (is-eq (get status paper) "under-review") ERR_PAPER_NOT_SUBMITTED)
    (asserts! (not (is-eq (get author paper) tx-sender)) ERR_NOT_AUTHORIZED)
    (asserts! (is-none existing-review) ERR_ALREADY_REVIEWED)
    (asserts! (and (>= score u1) (<= score u10)) ERR_INVALID_AMOUNT)
    
    (map-set reviews review-id
      {
        paper-id: paper-id,
        reviewer: tx-sender,
        score: score,
        feedback: feedback,
        review-block: stacks-block-height,
        reward-claimed: false
      }
    )
    (map-set user-reviews { paper-id: paper-id, reviewer: tx-sender } { review-id: review-id })
    (map-set papers paper-id
      (merge paper {
        review-count: (+ (get review-count paper) u1),
        total-score: (+ (get total-score paper) score)
      })
    )
    (var-set next-review-id (+ review-id u1))
    (ok review-id)
  )
)

(define-public (claim-review-reward (review-id uint))
  (let
    (
      (review (unwrap! (map-get? reviews review-id) ERR_REVIEW_NOT_FOUND))
      (paper (unwrap! (map-get? papers (get paper-id review)) ERR_PAPER_NOT_FOUND))
    )
    (asserts! (is-eq (get reviewer review) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (not (get reward-claimed review)) ERR_BOUNTY_CLAIMED)
    (asserts! (>= (get review-count paper) REVIEW_THRESHOLD) ERR_INSUFFICIENT_FUNDS)
    
    (try! (as-contract (stx-transfer? (get review-reward paper) tx-sender (get reviewer review))))
    (map-set reviews review-id
      (merge review { reward-claimed: true })
    )
    (ok true)
  )
)

(define-public (claim-author-bounty (paper-id uint))
  (let
    (
      (paper (unwrap! (map-get? papers paper-id) ERR_PAPER_NOT_FOUND))
      (average-score (/ (get total-score paper) (get review-count paper)))
      (platform-fee (/ (* (get bounty-amount paper) (var-get platform-fee-rate)) u10000))
      (author-reward (- (get bounty-amount paper) platform-fee))
    )
    (asserts! (is-eq (get author paper) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (not (get bounty-claimed paper)) ERR_BOUNTY_CLAIMED)
    (asserts! (>= (get review-count paper) REVIEW_THRESHOLD) ERR_INSUFFICIENT_FUNDS)
    (asserts! (>= average-score u7) ERR_INSUFFICIENT_FUNDS)
    
    (try! (as-contract (stx-transfer? author-reward tx-sender (get author paper))))
    (try! (as-contract (stx-transfer? platform-fee tx-sender CONTRACT_OWNER)))
    (map-set papers paper-id
      (merge paper { 
        bounty-claimed: true,
        status: "completed"
      })
    )
    (ok author-reward)
  )
)

(define-public (update-platform-fee (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (<= new-rate u1000) ERR_INVALID_AMOUNT)
    (var-set platform-fee-rate new-rate)
    (ok true)
  )
)

;; read only functions
(define-read-only (get-paper (paper-id uint))
  (map-get? papers paper-id)
)

(define-read-only (get-review (review-id uint))
  (map-get? reviews review-id)
)

(define-read-only (get-paper-funding (paper-id uint) (funder principal))
  (map-get? paper-funders { paper-id: paper-id, funder: funder })
)

(define-read-only (get-user-review (paper-id uint) (reviewer principal))
  (map-get? user-reviews { paper-id: paper-id, reviewer: reviewer })
)

(define-read-only (get-author-paper (author principal) (paper-index uint))
  (map-get? author-papers { author: author, paper-index: paper-index })
)

(define-read-only (get-author-paper-count (author principal))
  (default-to u0 (map-get? author-paper-count author))
)

(define-read-only (get-paper-average-score (paper-id uint))
  (match (map-get? papers paper-id)
    paper (if (> (get review-count paper) u0)
            (some (/ (get total-score paper) (get review-count paper)))
            none)
    none
  )
)

(define-read-only (get-next-paper-id)
  (var-get next-paper-id)
)

(define-read-only (get-next-review-id)
  (var-get next-review-id)
)

(define-read-only (get-platform-fee-rate)
  (var-get platform-fee-rate)
)

(define-read-only (can-claim-bounty (paper-id uint))
  (match (map-get? papers paper-id)
    paper (and 
            (>= (get review-count paper) REVIEW_THRESHOLD)
            (not (get bounty-claimed paper))
            (>= (/ (get total-score paper) (get review-count paper)) u7))
    false
  )
)

;; private functions