# MELA Central Admin Dashboard

Standalone administrative control plane for the MELA platform.

## Architecture

- Separate deployment from the consumer application
- Shared MELA Supabase/PostgreSQL backend
- Separate admin authentication entry point
- Role/permission-gated routes and API operations
- MFA required for privileged administrators
- Audited administrative writes
- Realtime operational monitoring

## Build order

1. Authorization and access control foundation
2. Audit logging
3. Operational dashboard
4. User/employer/payment/dispute operations
5. Content, mentorship and moderation
6. Notifications, analytics and system configuration

## Security rule

No admin UI action is trusted merely because it came from this application. Every privileged operation must be authorized server-side and recorded in the audit trail.
