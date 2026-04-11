# TODO: Fix Rejection Received - Sales Date Client/Item Dropdowns (Pagination + Dynamic Filtering)

## Status: [2/8 ✅ File Analyzed] 

**Issue**: After selecting Sale Date in rejection_received.dart, client/item dropdowns empty due to backend pagination (only 20 sales).

**Plan**:
1. Fix pagination: limit=200, full loop.
2. Date-specific clients/items from ALL sales.
3. Client dropdown: date clients > global.
4. Item filter: sales for date+client.
5. Debug SnackBar + logs.

## Steps:

### 1. ✅ Create TODO.md
### 2. ✅ Read/Analyze lib/rejection_received.dart

### 3. [PENDING] Fix Pagination
- _fetchPageSalesForDate(): limit=200
- _fetchAllSalesForDate(): log pages/data, fix hasMore

### 4. [PENDING] Add State Vars
- List<String> _dateClients = [], _dateItems = [];

### 5. [PENDING] Fix _onSaleDateChanged()
- Extract dateClients/items from _allSales
- setState + SnackBar "Loaded X sales, Y clients"

### 6. [PENDING] Client Dropdown
- Use _dateClients ?? _globalClients + "Other"

### 7. [PENDING] Fix _onClientChanged() &amp; Refresh
- Filter _allSales by client → update ALL rejectionItems.availableItems

### 8. [PENDING] Test &amp; Complete
- Hot reload, test date → client → item flow

**Next Tool**: edit_file lib/rejection_received.dart (pagination fixes)

