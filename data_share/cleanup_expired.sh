#!/bin/bash

# cleanup_expired.sh
# Automatically removes IAM users that have passed their expiration date
# Usage: ./cleanup_expired.sh [--dry-run]

set -e

DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "🔍 DRY RUN MODE - No changes will be made"
fi

echo "🔎 Scanning for expired IAM users with 'ExpiresOn' tag..."

# Get current date in YYYY-MM-DD format
CURRENT_DATE=$(date +%Y-%m-%d)

# Find all users with ExpiresOn tag
USERS=$(aws iam list-users --query 'Users[*].[UserName]' --output text)

EXPIRED_COUNT=0
ACTIVE_COUNT=0

for USER in $USERS; do
    # Get user tags
    TAGS=$(aws iam list-user-tags --user-name "$USER" --output json 2>/dev/null || echo '{"Tags":[]}')
    
    # Extract ExpiresOn tag
    EXPIRES_ON=$(echo "$TAGS" | jq -r '.Tags[] | select(.Key=="ExpiresOn") | .Value')
    
    if [[ -z "$EXPIRES_ON" || "$EXPIRES_ON" == "null" ]]; then
        continue
    fi
    
    # Compare dates
    if [[ "$EXPIRES_ON" < "$CURRENT_DATE" ]]; then
        echo "❌ EXPIRED: $USER (expired on $EXPIRES_ON)"
        EXPIRED_COUNT=$((EXPIRED_COUNT + 1))
        
        if [[ "$DRY_RUN" == false ]]; then
            echo "   Deleting user: $USER"
            
            # Delete access keys
            ACCESS_KEYS=$(aws iam list-access-keys --user-name "$USER" --query 'AccessKeyMetadata[*].AccessKeyId' --output text)
            for KEY in $ACCESS_KEYS; do
                echo "   - Deleting access key: $KEY"
                aws iam delete-access-key --user-name "$USER" --access-key-id "$KEY"
            done
            
            # Detach all user policies
            ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name "$USER" --query 'AttachedPolicies[*].PolicyArn' --output text)
            for POLICY_ARN in $ATTACHED_POLICIES; do
                echo "   - Detaching policy: $POLICY_ARN"
                aws iam detach-user-policy --user-name "$USER" --policy-arn "$POLICY_ARN"
                
                # Check if it's a customer-managed policy with the same name pattern
                if [[ "$POLICY_ARN" == *"policy/${USER}_policy"* ]]; then
                    echo "   - Deleting policy: $POLICY_ARN"
                    aws iam delete-policy --policy-arn "$POLICY_ARN"
                fi
            done
            
            # Delete inline policies
            INLINE_POLICIES=$(aws iam list-user-policies --user-name "$USER" --query 'PolicyNames[*]' --output text)
            for POLICY_NAME in $INLINE_POLICIES; do
                echo "   - Deleting inline policy: $POLICY_NAME"
                aws iam delete-user-policy --user-name "$USER" --policy-name "$POLICY_NAME"
            done
            
            # Delete the user
            echo "   - Deleting user: $USER"
            aws iam delete-user --user-name "$USER"
            echo "   ✅ User $USER deleted successfully"
        fi
    else
        echo "✅ ACTIVE: $USER (expires on $EXPIRES_ON)"
        ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
    fi
done

echo ""
echo "📊 Summary:"
echo "   Active users:  $ACTIVE_COUNT"
echo "   Expired users: $EXPIRED_COUNT"

if [[ "$DRY_RUN" == true && "$EXPIRED_COUNT" -gt 0 ]]; then
    echo ""
    echo "💡 Run without --dry-run to delete expired users"
fi

if [[ "$DRY_RUN" == false && "$EXPIRED_COUNT" -gt 0 ]]; then
    echo ""
    echo "✅ Cleanup complete!"
fi
