$users = @("tech1", "tech2", "guest1")
foreach ($user in $users) {
    # Check if user already exists
    if (-not (Get-LocalUser -Name $user -ErrorAction SilentlyContinue)) {
        New-LocalUser -Name $user `
            -Password (ConvertTo-SecureString "TempPass123!" -AsPlainText -Force) `
            -FullName "$user account" `
            -Description "Created by script"
        Write-Host "User $user created."
    } else {
        Write-Host "User $user already exists."
    }
    # Add user to Users group
    Add-LocalGroupMember -Group "Users" -Member $user -ErrorAction SilentlyContinue
}