# New Relic Alerts

Configure the following alerts in New Relic UI under **Alerts & AI → Alert Policies**:

## Policy: VoicePay Auth Service

### 1. High Error Rate (Critical)
- **Condition type:** NRQL
- **Query:** `SELECT percentage(count(*), WHERE error IS true) FROM Transaction WHERE appName = 'voicepay-auth'`
- **Threshold:** Above 5% for 5 minutes
- **Severity:** Critical

### 2. High Response Time (Warning)
- **Condition type:** NRQL
- **Query:** `SELECT average(duration) FROM Transaction WHERE appName = 'voicepay-auth'`
- **Threshold:** Above 1 second for 5 minutes
- **Severity:** Warning

### 3. Application Not Reporting (Critical)
- **Condition type:** APM - Application not reporting
- **Application:** voicepay-auth
- **Threshold:** Not reporting for 5 minutes
- **Severity:** Critical

## Setup Steps

1. Go to **Alerts & AI** → **Alert Policies** → **Create a policy**
2. Name: `VoicePay Auth Service`
3. Add the 3 conditions above
4. Configure notification channel (email, Slack, etc.)
