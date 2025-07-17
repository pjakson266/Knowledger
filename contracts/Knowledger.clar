
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
(define-constant ERR_PARTNERSHIP_NOT_FOUND (err u109))
(define-constant ERR_ALREADY_PARTNERED (err u110))
(define-constant ERR_PARTNERSHIP_PENDING (err u111))
(define-constant ERR_INVALID_PARTNERSHIP (err u112))
(define-constant ERR_INSUFFICIENT_STAKE (err u113))
(define-constant ERR_RESOURCE_NOT_FOUND (err u114))
(define-constant ERR_ACHIEVEMENT_NOT_FOUND (err u115))
(define-constant MIN_BOUNTY_AMOUNT u1000000)
(define-constant MIN_REVIEW_REWARD u100000)
(define-constant REVIEW_THRESHOLD u3)
(define-constant MIN_PARTNERSHIP_STAKE u500000)
(define-constant MAX_PARTNERSHIP_SIZE u10)

;; data vars
(define-data-var next-paper-id uint u1)
(define-data-var next-review-id uint u1)
(define-data-var platform-fee-rate uint u250)
(define-data-var next-partnership-id uint u1)
(define-data-var next-resource-id uint u1)
(define-data-var next-achievement-id uint u1)

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

(define-map partnerships
  uint
  {
    name: (string-ascii 128),
    description: (string-ascii 512),
    creator: principal,
    total-stake: uint,
    member-count: uint,
    status: (string-ascii 20),
    creation-block: uint,
    max-members: uint
  }
)

(define-map partnership-members
  { partnership-id: uint, member: principal }
  {
    stake-amount: uint,
    join-block: uint,
    role: (string-ascii 50),
    active: bool
  }
)

(define-map partnership-invites
  { partnership-id: uint, invitee: principal }
  {
    inviter: principal,
    invite-block: uint,
    status: (string-ascii 20)
  }
)

(define-map shared-resources
  uint
  {
    partnership-id: uint,
    resource-type: (string-ascii 50),
    title: (string-ascii 256),
    description: (string-ascii 512),
    contributor: principal,
    creation-block: uint,
    access-level: (string-ascii 20)
  }
)

(define-map collaborative-papers
  { partnership-id: uint, paper-id: uint }
  {
    contributors: (list 10 principal),
    contribution-shares: (list 10 uint),
    total-shares: uint
  }
)

(define-map partnership-achievements
  uint
  {
    partnership-id: uint,
    achievement-type: (string-ascii 50),
    title: (string-ascii 256),
    description: (string-ascii 512),
    achieved-by: principal,
    achievement-block: uint,
    value: uint
  }
)

(define-map user-partnerships
  { user: principal, partnership-index: uint }
  { partnership-id: uint }
)

(define-map user-partnership-count
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

(define-public (create-partnership (name (string-ascii 128)) (description (string-ascii 512)) (max-members uint) (stake-amount uint))
  (let
    (
      (partnership-id (var-get next-partnership-id))
      (current-count (default-to u0 (map-get? user-partnership-count tx-sender)))
    )
    (asserts! (>= stake-amount MIN_PARTNERSHIP_STAKE) ERR_INSUFFICIENT_STAKE)
    (asserts! (and (> max-members u1) (<= max-members MAX_PARTNERSHIP_SIZE)) ERR_INVALID_PARTNERSHIP)
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    (map-set partnerships partnership-id
      {
        name: name,
        description: description,
        creator: tx-sender,
        total-stake: stake-amount,
        member-count: u1,
        status: "active",
        creation-block: stacks-block-height,
        max-members: max-members
      }
    )
    (map-set partnership-members { partnership-id: partnership-id, member: tx-sender }
      {
        stake-amount: stake-amount,
        join-block: stacks-block-height,
        role: "founder",
        active: true
      }
    )
    (map-set user-partnerships { user: tx-sender, partnership-index: current-count } { partnership-id: partnership-id })
    (map-set user-partnership-count tx-sender (+ current-count u1))
    (var-set next-partnership-id (+ partnership-id u1))
    (ok partnership-id)
  )
)

(define-public (invite-to-partnership (partnership-id uint) (invitee principal))
  (let
    (
      (partnership (unwrap! (map-get? partnerships partnership-id) ERR_PARTNERSHIP_NOT_FOUND))
      (member (unwrap! (map-get? partnership-members { partnership-id: partnership-id, member: tx-sender }) ERR_NOT_AUTHORIZED))
      (existing-invite (map-get? partnership-invites { partnership-id: partnership-id, invitee: invitee }))
      (existing-member (map-get? partnership-members { partnership-id: partnership-id, member: invitee }))
    )
    (asserts! (get active member) ERR_NOT_AUTHORIZED)
    (asserts! (is-none existing-invite) ERR_ALREADY_PARTNERED)
    (asserts! (is-none existing-member) ERR_ALREADY_PARTNERED)
    (asserts! (< (get member-count partnership) (get max-members partnership)) ERR_INVALID_PARTNERSHIP)
    
    (map-set partnership-invites { partnership-id: partnership-id, invitee: invitee }
      {
        inviter: tx-sender,
        invite-block: stacks-block-height,
        status: "pending"
      }
    )
    (ok true)
  )
)

(define-public (join-partnership (partnership-id uint) (stake-amount uint))
  (let
    (
      (partnership (unwrap! (map-get? partnerships partnership-id) ERR_PARTNERSHIP_NOT_FOUND))
      (invite (unwrap! (map-get? partnership-invites { partnership-id: partnership-id, invitee: tx-sender }) ERR_PARTNERSHIP_PENDING))
      (current-count (default-to u0 (map-get? user-partnership-count tx-sender)))
    )
    (asserts! (>= stake-amount MIN_PARTNERSHIP_STAKE) ERR_INSUFFICIENT_STAKE)
    (asserts! (is-eq (get status invite) "pending") ERR_PARTNERSHIP_PENDING)
    (asserts! (< (get member-count partnership) (get max-members partnership)) ERR_INVALID_PARTNERSHIP)
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    (map-set partnership-members { partnership-id: partnership-id, member: tx-sender }
      {
        stake-amount: stake-amount,
        join-block: stacks-block-height,
        role: "member",
        active: true
      }
    )
    (map-set partnership-invites { partnership-id: partnership-id, invitee: tx-sender }
      (merge invite { status: "accepted" })
    )
    (map-set partnerships partnership-id
      (merge partnership {
        member-count: (+ (get member-count partnership) u1),
        total-stake: (+ (get total-stake partnership) stake-amount)
      })
    )
    (map-set user-partnerships { user: tx-sender, partnership-index: current-count } { partnership-id: partnership-id })
    (map-set user-partnership-count tx-sender (+ current-count u1))
    (ok true)
  )
)

(define-public (share-resource (partnership-id uint) (resource-type (string-ascii 50)) (title (string-ascii 256)) (description (string-ascii 512)) (access-level (string-ascii 20)))
  (let
    (
      (resource-id (var-get next-resource-id))
      (member (unwrap! (map-get? partnership-members { partnership-id: partnership-id, member: tx-sender }) ERR_NOT_AUTHORIZED))
    )
    (asserts! (get active member) ERR_NOT_AUTHORIZED)
    
    (map-set shared-resources resource-id
      {
        partnership-id: partnership-id,
        resource-type: resource-type,
        title: title,
        description: description,
        contributor: tx-sender,
        creation-block: stacks-block-height,
        access-level: access-level
      }
    )
    (var-set next-resource-id (+ resource-id u1))
    (ok resource-id)
  )
)

(define-public (register-collaborative-paper (partnership-id uint) (paper-id uint) (contributors (list 10 principal)) (shares (list 10 uint)))
  (let
    (
      (partnership (unwrap! (map-get? partnerships partnership-id) ERR_PARTNERSHIP_NOT_FOUND))
      (paper (unwrap! (map-get? papers paper-id) ERR_PAPER_NOT_FOUND))
      (member (unwrap! (map-get? partnership-members { partnership-id: partnership-id, member: tx-sender }) ERR_NOT_AUTHORIZED))
      (total-shares (fold + shares u0))
    )
    (asserts! (get active member) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (len contributors) (len shares)) ERR_INVALID_AMOUNT)
    (asserts! (> total-shares u0) ERR_INVALID_AMOUNT)
    
    (map-set collaborative-papers { partnership-id: partnership-id, paper-id: paper-id }
      {
        contributors: contributors,
        contribution-shares: shares,
        total-shares: total-shares
      }
    )
    (ok true)
  )
)

(define-public (record-achievement (partnership-id uint) (achievement-type (string-ascii 50)) (title (string-ascii 256)) (description (string-ascii 512)) (value uint))
  (let
    (
      (achievement-id (var-get next-achievement-id))
      (member (unwrap! (map-get? partnership-members { partnership-id: partnership-id, member: tx-sender }) ERR_NOT_AUTHORIZED))
    )
    (asserts! (get active member) ERR_NOT_AUTHORIZED)
    
    (map-set partnership-achievements achievement-id
      {
        partnership-id: partnership-id,
        achievement-type: achievement-type,
        title: title,
        description: description,
        achieved-by: tx-sender,
        achievement-block: stacks-block-height,
        value: value
      }
    )
    (var-set next-achievement-id (+ achievement-id u1))
    (ok achievement-id)
  )
)

(define-public (leave-partnership (partnership-id uint))
  (let
    (
      (partnership (unwrap! (map-get? partnerships partnership-id) ERR_PARTNERSHIP_NOT_FOUND))
      (member (unwrap! (map-get? partnership-members { partnership-id: partnership-id, member: tx-sender }) ERR_NOT_AUTHORIZED))
      (refund-amount (/ (get stake-amount member) u2))
    )
    (asserts! (get active member) ERR_NOT_AUTHORIZED)
    (asserts! (not (is-eq (get creator partnership) tx-sender)) ERR_NOT_AUTHORIZED)
    
    (try! (as-contract (stx-transfer? refund-amount tx-sender tx-sender)))
    (map-set partnership-members { partnership-id: partnership-id, member: tx-sender }
      (merge member { active: false })
    )
    (map-set partnerships partnership-id
      (merge partnership {
        member-count: (- (get member-count partnership) u1),
        total-stake: (- (get total-stake partnership) (get stake-amount member))
      })
    )
    (ok refund-amount)
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

(define-read-only (get-partnership (partnership-id uint))
  (map-get? partnerships partnership-id)
)

(define-read-only (get-partnership-member (partnership-id uint) (member principal))
  (map-get? partnership-members { partnership-id: partnership-id, member: member })
)

(define-read-only (get-partnership-invite (partnership-id uint) (invitee principal))
  (map-get? partnership-invites { partnership-id: partnership-id, invitee: invitee })
)

(define-read-only (get-shared-resource (resource-id uint))
  (map-get? shared-resources resource-id)
)

(define-read-only (get-collaborative-paper (partnership-id uint) (paper-id uint))
  (map-get? collaborative-papers { partnership-id: partnership-id, paper-id: paper-id })
)

(define-read-only (get-partnership-achievement (achievement-id uint))
  (map-get? partnership-achievements achievement-id)
)

(define-read-only (get-user-partnership (user principal) (partnership-index uint))
  (map-get? user-partnerships { user: user, partnership-index: partnership-index })
)

(define-read-only (get-user-partnership-count (user principal))
  (default-to u0 (map-get? user-partnership-count user))
)

(define-read-only (get-next-partnership-id)
  (var-get next-partnership-id)
)

(define-read-only (get-next-resource-id)
  (var-get next-resource-id)
)

(define-read-only (get-next-achievement-id)
  (var-get next-achievement-id)
)

(define-read-only (get-partnership-total-stake (partnership-id uint))
  (match (map-get? partnerships partnership-id)
    partnership (some (get total-stake partnership))
    none
  )
)

(define-read-only (is-partnership-member (partnership-id uint) (user principal))
  (match (map-get? partnership-members { partnership-id: partnership-id, member: user })
    member (get active member)
    false
  )
)

;; private functions