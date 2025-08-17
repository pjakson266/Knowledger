# 📚 Knowledger - Academic Paper Bounties

> 🎓 A decentralized platform for funding open research papers and incentivizing peer review on the Stacks blockchain

## 🌟 Overview

Knowledger revolutionizes academic publishing by creating a bounty system where:
- 📝 Authors can create research papers and set review rewards
- 💰 Community members can fund promising research with STX bounties  
- 👥 Peer reviewers earn rewards for quality reviews
- 🏆 Authors earn bounties when their papers receive high scores

## ✨ Features

- **Paper Creation**: Authors submit research papers with abstracts and set reviewer rewards
- **Community Funding**: Anyone can contribute STX to fund research bounties
- **Peer Review System**: Qualified reviewers score papers (1-10) and provide feedback
- **Reward Distribution**: Automatic payouts for reviewers and successful authors
- **Quality Threshold**: Papers need ≥3 reviews with average score ≥7 to claim bounties

## 🚀 Getting Started

### Prerequisites
- Clarinet CLI installed
- Stacks wallet with STX tokens

### Installation

```bash
git clone <repository-url>
cd knowledger
clarinet check
```

## 📖 Usage Guide

### For Authors 👨‍🎓

1. **Create a Paper**
   ```clarity
   (contract-call? .Knowledger create-paper 
     "Revolutionary Blockchain Research" 
     "This paper explores..." 
     u500000) ;; 0.5 STX review reward
   ```

2. **Submit for Review** (after funding reaches minimum)
   ```clarity
   (contract-call? .Knowledger submit-paper-for-review u1)
   ```

3. **Claim Bounty** (after 3+ reviews with avg score ≥7)
   ```clarity
   (contract-call? .Knowledger claim-author-bounty u1)
   ```

### For Funders 💰

**Fund Research Papers**
```clarity
(contract-call? .Knowledger fund-paper u1 u2000000) ;; Fund 2 STX
```

### For Reviewers 🔍

1. **Submit Review**
   ```clarity
   (contract-call? .Knowledger submit-review 
     u1 u8 "Excellent methodology and clear results")
   ```

2. **Claim Review Reward**
   ```clarity
   (contract-call? .Knowledger claim-review-reward u1)
   ```

## 🔧 Contract Functions

### Public Functions
- `create-paper` - Create new research paper
- `fund-paper` - Add STX bounty to paper
- `submit-paper-for-review` - Make paper available for review
- `submit-review` - Submit peer review with score
- `claim-review-reward` - Claim STX reward for reviewing
- `claim-author-bounty` - Claim STX bounty for successful paper

### Read-Only Functions
- `get-paper` - Get paper details
- `get-review` - Get review details  
- `get-paper-average-score` - Calculate average review score
- `can-claim-bounty` - Check if paper qualifies for bounty

## 💡 Key Parameters

- **Minimum Bounty**: 1 STX (1,000,000 microSTX)
- **Minimum Review Reward**: 0.1 STX (100,000 microSTX)  
- **Review Threshold**: 3 reviews required
- **Success Score**: ≥7.0 average rating
- **Platform Fee**: 2.5% of bounties

## 🛡️ Security Features

- Author authorization checks
- Duplicate review prevention
- Bounty claim validation
- Minimum funding requirements
- Score validation (1-10 range)


