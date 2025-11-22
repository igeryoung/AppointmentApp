# API Documentation UI

## Overview
Access the interactive Swagger UI for exploring and testing the API.

## Endpoint
```
GET /docs
```

## Authentication
None (public endpoint)

## Request Parameters
None

## Response

### Success Response (301 Moved Permanently)
Redirects to the Swagger UI interface.

**Redirect Location:** `/docs/`

## Error Scenarios
- **404 Not Found**: If Swagger UI files are not installed

## Usage Notes
- Provides an interactive web interface to explore all API endpoints
- Can test API calls directly from the browser
- Includes request/response examples and schema documentation
- No authentication required to view documentation
- Authentication credentials can be entered in the UI to test protected endpoints
- Redirect ensures proper trailing slash for static file serving
