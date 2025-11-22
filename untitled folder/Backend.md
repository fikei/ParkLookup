# Backend Future Specification: SF Parking Zone Finder

**Version:** 1.0
**Last Updated:** November 2025
**Status:** Draft (Future Implementation)
**Authors:** Engineering Team

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [API Specification](#api-specification)
4. [Data Pipeline](#data-pipeline)
5. [Database Design](#database-design)
6. [Caching Strategy](#caching-strategy)
7. [Multi-City Support](#multi-city-support)
8. [Security & Privacy](#security--privacy)
9. [Infrastructure](#infrastructure)
10. [Open Decisions](#open-decisions)

---

## Overview

This document specifies the backend architecture for SF Parking Zone Finder V2.0, which will replace the embedded mock data with a live API service. The backend will:

- Serve parking zone data for multiple cities
- Provide zone lookup by coordinates
- Sync data from official sources (DataSF, SFMTA)
- Support offline-capable mobile clients
- Scale horizontally for future growth

### Timeline

| Phase | Description | Target |
|-------|-------------|--------|
| **V1.0 (MVP)** | No backend - embedded JSON | Current |
| **V1.1** | No backend - improved mock data | Post-MVP |
| **V2.0** | Backend API live | Future |

---

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Client Layer                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌──────────────┐    ┌──────────────┐    ┌──────────────┐         │
│   │   iOS App    │    │ Android App  │    │   Web App    │         │
│   │   (Swift)    │    │   (Kotlin)   │    │   (React)    │         │
│   └──────┬───────┘    └──────┬───────┘    └──────┬───────┘         │
│          │                   │                   │                  │
└──────────┼───────────────────┼───────────────────┼──────────────────┘
           │                   │                   │
           └───────────────────┼───────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          API Gateway                                 │
│                     (Rate Limiting, Auth)                           │
└─────────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        Application Layer                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌──────────────────────────────────────────────────────────┐      │
│   │                   API Service                             │      │
│   │   ┌────────────┐  ┌────────────┐  ┌────────────┐        │      │
│   │   │   Zone     │  │   Lookup   │  │   City     │        │      │
│   │   │  Endpoint  │  │  Endpoint  │  │  Endpoint  │        │      │
│   │   └────────────┘  └────────────┘  └────────────┘        │      │
│   └──────────────────────────────────────────────────────────┘      │
│                               │                                      │
└───────────────────────────────┼──────────────────────────────────────┘
                               │
           ┌───────────────────┼───────────────────┐
           │                   │                   │
           ▼                   ▼                   ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│   Cache Layer    │ │  Database Layer  │ │  Data Pipeline   │
│     (Redis)      │ │ (PostgreSQL +    │ │   (Scheduled)    │
│                  │ │    PostGIS)      │ │                  │
└──────────────────┘ └──────────────────┘ └──────────────────┘
                               │                   │
                               │                   │
                               │           ┌───────┴───────┐
                               │           │               │
                               │           ▼               ▼
                               │    ┌────────────┐  ┌────────────┐
                               │    │  DataSF    │  │   SFMTA    │
                               │    │    API     │  │    API     │
                               │    └────────────┘  └────────────┘
                               │
                               ▼
                    ┌──────────────────┐
                    │  Spatial Index   │
                    │ (PostGIS R-tree) │
                    └──────────────────┘
```

### Technology Stack (Recommended)

| Component | Technology | Rationale |
|-----------|------------|-----------|
| **API Framework** | FastAPI (Python) or Go | FastAPI: rapid development, async; Go: performance |
| **Database** | PostgreSQL + PostGIS | Industry standard for geospatial data |
| **Cache** | Redis | Fast, supports geospatial queries |
| **API Gateway** | AWS API Gateway / Kong | Rate limiting, auth, monitoring |
| **Hosting** | AWS / GCP | Scalability, managed services |
| **CI/CD** | GitHub Actions | Integration with repository |

---

## API Specification

### Base URL

```
Production: https://api.sfparkingzone.app/v1
Staging:    https://api-staging.sfparkingzone.app/v1
```

### Authentication

**V2.0:** API key for rate limiting (no user auth required for public endpoints)

```http
X-API-Key: <client-api-key>
```

### Endpoints

#### GET /cities

List all supported cities.

**Response:**
```json
{
  "success": true,
  "data": {
    "cities": [
      {
        "code": "sf",
        "name": "San Francisco",
        "state": "CA",
        "bounds": {
          "north": 37.8324,
          "south": 37.6398,
          "east": -122.3281,
          "west": -122.5274
        },
        "dataVersion": "2025.11.1",
        "lastUpdated": "2025-11-15T00:00:00Z",
        "permitTypes": ["rpp"],
        "isActive": true
      },
      {
        "code": "oak",
        "name": "Oakland",
        "state": "CA",
        "bounds": { ... },
        "dataVersion": "2025.11.1",
        "lastUpdated": "2025-11-15T00:00:00Z",
        "permitTypes": ["rpp"],
        "isActive": true
      }
    ]
  }
}
```

#### GET /cities/{code}/zones

Get all zones for a specific city.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| code | path | Yes | City code (e.g., "sf") |
| updated_since | query | No | ISO8601 timestamp for delta sync |
| include_geometry | query | No | Include polygon coordinates (default: true) |

**Response:**
```json
{
  "success": true,
  "data": {
    "city": "sf",
    "dataVersion": "2025.11.1",
    "lastUpdated": "2025-11-15T00:00:00Z",
    "zones": [
      {
        "id": "sf_rpp_q_001",
        "displayName": "Area Q",
        "zoneType": "rpp",
        "permitArea": "Q",
        "validPermitAreas": ["Q"],
        "requiresPermit": true,
        "restrictiveness": 8,
        "boundary": {
          "type": "Polygon",
          "coordinates": [[[-122.4359, 37.7599], ...]]
        },
        "rules": [...],
        "metadata": {
          "dataSource": "sfmta",
          "lastUpdated": "2025-11-01T00:00:00Z",
          "accuracy": "high"
        }
      }
    ],
    "totalCount": 150,
    "hasMore": false
  }
}
```

#### POST /lookup

Find zone(s) for a specific coordinate.

**Request:**
```json
{
  "latitude": 37.7599,
  "longitude": -122.4359,
  "cityCode": "sf"  // Optional - auto-detect if omitted
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "coordinate": {
      "latitude": 37.7599,
      "longitude": -122.4359
    },
    "city": {
      "code": "sf",
      "name": "San Francisco"
    },
    "result": {
      "primaryZone": {
        "id": "sf_rpp_q_001",
        "displayName": "Area Q",
        "zoneType": "rpp",
        "permitArea": "Q",
        "validPermitAreas": ["Q"],
        "requiresPermit": true,
        "rules": [...]
      },
      "overlappingZones": [],
      "confidence": "high",
      "nearestBoundaryDistance": 45.2  // meters to nearest zone edge
    },
    "timestamp": "2025-11-21T10:30:00Z"
  }
}
```

**Error Response (outside coverage):**
```json
{
  "success": false,
  "error": {
    "code": "OUTSIDE_COVERAGE",
    "message": "Location is outside supported coverage area",
    "details": {
      "nearestCity": {
        "code": "sf",
        "name": "San Francisco",
        "distance": 1234.5  // meters
      }
    }
  }
}
```

#### GET /zones/{id}

Get detailed information for a specific zone.

**Response:**
```json
{
  "success": true,
  "data": {
    "zone": {
      "id": "sf_rpp_q_001",
      "cityCode": "sf",
      "displayName": "Area Q",
      "zoneType": "rpp",
      "permitArea": "Q",
      "validPermitAreas": ["Q"],
      "requiresPermit": true,
      "restrictiveness": 8,
      "boundary": {
        "type": "Polygon",
        "coordinates": [[...]]
      },
      "rules": [
        {
          "id": "rule_001",
          "ruleType": "permit_required",
          "description": "Residential Permit Area Q only",
          "enforcementDays": ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday"],
          "enforcementStartTime": "08:00",
          "enforcementEndTime": "18:00",
          "timeLimit": 120,
          "specialConditions": "2-hour limit for non-permit holders"
        }
      ],
      "metadata": {
        "dataSource": "sfmta",
        "lastUpdated": "2025-11-01T00:00:00Z",
        "accuracy": "high"
      }
    }
  }
}
```

#### GET /health

Health check endpoint.

**Response:**
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "timestamp": "2025-11-21T10:30:00Z",
  "dependencies": {
    "database": "healthy",
    "cache": "healthy"
  }
}
```

### Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| INVALID_REQUEST | 400 | Malformed request body |
| INVALID_COORDINATES | 400 | Coordinates out of valid range |
| CITY_NOT_FOUND | 404 | Requested city code not supported |
| ZONE_NOT_FOUND | 404 | Requested zone ID not found |
| OUTSIDE_COVERAGE | 404 | Coordinates outside any supported city |
| RATE_LIMITED | 429 | Too many requests |
| INTERNAL_ERROR | 500 | Server error |

### Rate Limits

| Client Type | Requests/min | Requests/day |
|-------------|--------------|--------------|
| Free tier | 60 | 10,000 |
| Premium tier | 300 | 100,000 |
| Enterprise | Custom | Custom |

---

## Data Pipeline

### Data Sources

| Source | Data Type | Update Frequency | Format |
|--------|-----------|------------------|--------|
| **DataSF** | Parking meters, street segments | Daily | CSV/API |
| **SFMTA** | RPP boundaries, meter pricing | Weekly | GeoJSON/API |
| **Manual** | Corrections, edge cases | As needed | JSON |

### Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Data Pipeline                                 │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   DataSF     │     │    SFMTA     │     │   Manual     │
│   Source     │     │   Source     │     │  Overrides   │
└──────┬───────┘     └──────┬───────┘     └──────┬───────┘
       │                    │                    │
       └────────────────────┼────────────────────┘
                            │
                            ▼
               ┌──────────────────────┐
               │      Extractor       │
               │  (Fetch raw data)    │
               └──────────┬───────────┘
                          │
                          ▼
               ┌──────────────────────┐
               │     Transformer      │
               │  - Normalize schema  │
               │  - Validate geometry │
               │  - Apply overrides   │
               │  - Merge duplicates  │
               └──────────┬───────────┘
                          │
                          ▼
               ┌──────────────────────┐
               │       Loader         │
               │  - Update database   │
               │  - Rebuild indexes   │
               │  - Invalidate cache  │
               │  - Version increment │
               └──────────┬───────────┘
                          │
                          ▼
               ┌──────────────────────┐
               │      Validator       │
               │  - Smoke tests       │
               │  - Coverage check    │
               │  - Alert on issues   │
               └──────────────────────┘
```

### Pipeline Schedule

| Task | Frequency | Time (UTC) |
|------|-----------|------------|
| DataSF sync | Daily | 02:00 |
| SFMTA sync | Weekly (Sunday) | 03:00 |
| Data validation | After each sync | Automated |
| Manual review | Weekly | Ad-hoc |

### Data Validation Rules

| Rule | Action |
|------|--------|
| Invalid geometry (self-intersecting) | Flag for manual review |
| Missing required fields | Reject record |
| Duplicate zone ID | Merge or reject |
| Boundary outside city bounds | Flag for review |
| Rule with invalid time format | Reject rule |

---

## Database Design

### Schema Overview

```sql
-- Cities table
CREATE TABLE cities (
    code VARCHAR(10) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    state VARCHAR(2) NOT NULL,
    bounds GEOMETRY(POLYGON, 4326) NOT NULL,
    data_version VARCHAR(20) NOT NULL,
    last_updated TIMESTAMP WITH TIME ZONE NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Permit areas table
CREATE TABLE permit_areas (
    id SERIAL PRIMARY KEY,
    city_code VARCHAR(10) REFERENCES cities(code),
    area_code VARCHAR(10) NOT NULL,
    name VARCHAR(100) NOT NULL,
    neighborhoods TEXT[],
    UNIQUE(city_code, area_code)
);

-- Parking zones table
CREATE TABLE parking_zones (
    id VARCHAR(50) PRIMARY KEY,
    city_code VARCHAR(10) REFERENCES cities(code),
    display_name VARCHAR(100) NOT NULL,
    zone_type VARCHAR(20) NOT NULL,
    permit_area VARCHAR(10),
    valid_permit_areas TEXT[] NOT NULL DEFAULT '{}',
    requires_permit BOOLEAN NOT NULL DEFAULT false,
    restrictiveness INTEGER NOT NULL DEFAULT 5,
    boundary GEOMETRY(POLYGON, 4326) NOT NULL,
    data_source VARCHAR(50) NOT NULL,
    source_accuracy VARCHAR(20) NOT NULL DEFAULT 'medium',
    last_updated TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Spatial index for fast lookups
CREATE INDEX idx_parking_zones_boundary
ON parking_zones USING GIST (boundary);

-- Index for city-based queries
CREATE INDEX idx_parking_zones_city
ON parking_zones (city_code);

-- Parking rules table
CREATE TABLE parking_rules (
    id VARCHAR(50) PRIMARY KEY,
    zone_id VARCHAR(50) REFERENCES parking_zones(id) ON DELETE CASCADE,
    rule_type VARCHAR(30) NOT NULL,
    description TEXT NOT NULL,
    enforcement_days TEXT[],
    enforcement_start_time TIME,
    enforcement_end_time TIME,
    time_limit_minutes INTEGER,
    meter_rate_cents INTEGER,
    special_conditions TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_parking_rules_zone
ON parking_rules (zone_id);

-- Data versions table (for delta sync)
CREATE TABLE data_versions (
    id SERIAL PRIMARY KEY,
    city_code VARCHAR(10) REFERENCES cities(code),
    version VARCHAR(20) NOT NULL,
    published_at TIMESTAMP WITH TIME ZONE NOT NULL,
    changes_summary JSONB,
    UNIQUE(city_code, version)
);
```

### Geospatial Queries

```sql
-- Find zone containing a point
SELECT z.*,
       ST_Distance(z.boundary::geography,
                   ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography) as distance_meters
FROM parking_zones z
WHERE z.city_code = $3
  AND ST_Contains(z.boundary, ST_SetSRID(ST_MakePoint($1, $2), 4326))
ORDER BY z.restrictiveness DESC;

-- Find zones near a point (for boundary detection)
SELECT z.*,
       ST_Distance(z.boundary::geography,
                   ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography) as distance_meters
FROM parking_zones z
WHERE z.city_code = $3
  AND ST_DWithin(z.boundary::geography,
                 ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
                 $4)  -- distance threshold in meters
ORDER BY distance_meters ASC;

-- Detect which city contains a point
SELECT c.code, c.name
FROM cities c
WHERE ST_Contains(c.bounds, ST_SetSRID(ST_MakePoint($1, $2), 4326))
  AND c.is_active = true;
```

---

## Caching Strategy

### Cache Layers

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Caching Architecture                          │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Client     │     │   Redis      │     │  PostgreSQL  │
│   Cache      │ ◄── │   Cache      │ ◄── │  (Source)    │
│              │     │              │     │              │
└──────────────┘     └──────────────┘     └──────────────┘

  - Zone data        - Zone data          - All data
    (local storage)    (5 min TTL)         (persistent)
  - Lookup results   - Lookup results
    (5 min TTL)        (1 min TTL)
```

### Cache Keys

| Key Pattern | Data | TTL |
|-------------|------|-----|
| `city:{code}:zones` | All zones for city | 5 minutes |
| `city:{code}:version` | Data version | 1 minute |
| `lookup:{lat}:{lon}:{precision}` | Zone lookup result | 1 minute |
| `zone:{id}` | Single zone details | 5 minutes |

### Cache Invalidation

| Trigger | Action |
|---------|--------|
| Data pipeline completes | Invalidate all zone caches for city |
| Manual data update | Invalidate affected zone caches |
| Version increment | Clients detect via version check |

### Client-Side Caching

```swift
// iOS client caching strategy
struct CacheConfig {
    static let zoneCacheTTL: TimeInterval = 24 * 60 * 60  // 24 hours
    static let lookupCacheTTL: TimeInterval = 5 * 60     // 5 minutes
    static let versionCheckInterval: TimeInterval = 60    // 1 minute
}

// Cache validation flow:
// 1. Check local cache for zone data
// 2. If cache exists, check version against server
// 3. If version matches, use cache
// 4. If version differs, fetch updated zones
// 5. If offline, use cache regardless of version
```

---

## Multi-City Support

### City Configuration

Each city requires:

| Requirement | Description |
|-------------|-------------|
| **City bounds** | Bounding box polygon for city detection |
| **Data sources** | Configured pipeline sources for city |
| **Permit types** | List of permit types available |
| **Zone schema** | City-specific zone type mappings |
| **Update schedule** | Pipeline schedule for city data |

### Adding a New City

1. **Data sourcing:** Identify official data sources
2. **Schema mapping:** Map source schema to standard schema
3. **Pipeline configuration:** Add city to data pipeline
4. **Validation:** Verify data quality and coverage
5. **Testing:** Field test in target city
6. **Activation:** Enable city in API

### City Detection Logic

```python
def detect_city(latitude: float, longitude: float) -> Optional[City]:
    """
    Determine which city contains the given coordinates.
    Returns None if outside all supported cities.
    """
    point = f"POINT({longitude} {latitude})"

    city = db.query("""
        SELECT code, name
        FROM cities
        WHERE ST_Contains(bounds, ST_GeomFromText(%s, 4326))
          AND is_active = true
    """, [point]).first()

    return city
```

---

## Security & Privacy

### Privacy Principles

| Principle | Implementation |
|-----------|----------------|
| **No location logging** | Coordinates in lookup requests not stored |
| **No user tracking** | No user accounts required for basic API |
| **Minimal data collection** | Only aggregate analytics (request counts) |
| **Encryption in transit** | HTTPS required for all endpoints |

### Security Measures

| Measure | Implementation |
|---------|----------------|
| **API authentication** | API keys for rate limiting |
| **Rate limiting** | Per-key limits enforced at gateway |
| **Input validation** | Strict coordinate range validation |
| **SQL injection prevention** | Parameterized queries only |
| **CORS** | Restricted to known client origins |

### API Key Management

```python
# API key validation
async def validate_api_key(request: Request) -> APIKey:
    key = request.headers.get("X-API-Key")
    if not key:
        raise HTTPException(401, "API key required")

    api_key = await db.get_api_key(key)
    if not api_key or not api_key.is_active:
        raise HTTPException(401, "Invalid API key")

    # Check rate limits
    if await rate_limiter.is_exceeded(api_key):
        raise HTTPException(429, "Rate limit exceeded")

    return api_key
```

---

## Infrastructure

### Deployment Architecture (AWS)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AWS Infrastructure                           │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                        Route 53 (DNS)                         │
└──────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                    CloudFront (CDN)                           │
└──────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│              API Gateway (Rate Limiting, Auth)                │
└──────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                   Application Load Balancer                   │
└──────────────────────────────────────────────────────────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
       ┌────────────┐   ┌────────────┐   ┌────────────┐
       │   ECS      │   │   ECS      │   │   ECS      │
       │  Task 1    │   │  Task 2    │   │  Task 3    │
       │ (API Svc)  │   │ (API Svc)  │   │ (API Svc)  │
       └────────────┘   └────────────┘   └────────────┘
              │                │                │
              └────────────────┼────────────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                                 ▼
       ┌────────────┐                    ┌────────────┐
       │ ElastiCache│                    │    RDS     │
       │  (Redis)   │                    │ PostgreSQL │
       │            │                    │ + PostGIS  │
       └────────────┘                    └────────────┘
```

### Environment Configuration

| Environment | Purpose | Scale |
|-------------|---------|-------|
| **Development** | Local development | Single instance |
| **Staging** | Integration testing | 2 ECS tasks |
| **Production** | Live traffic | 3+ ECS tasks (auto-scaling) |

### Monitoring & Alerting

| Metric | Alert Threshold | Action |
|--------|-----------------|--------|
| API error rate | >1% | Page on-call |
| API latency (p99) | >500ms | Investigate |
| Database CPU | >80% | Scale up |
| Cache hit rate | <80% | Review cache config |
| Pipeline failure | Any | Alert + retry |

---

## Open Decisions

| Decision | Options | Recommendation | Status |
|----------|---------|----------------|--------|
| **Backend language** | Python (FastAPI), Go, Node.js | FastAPI (rapid development) | Open |
| **Cloud provider** | AWS, GCP, Azure | AWS (team familiarity) | Open |
| **Database hosting** | RDS, Cloud SQL, Self-managed | RDS PostgreSQL | Open |
| **CI/CD for backend** | GitHub Actions, CircleCI | GitHub Actions | Open |
| **API versioning** | URL path, header | URL path (/v1/) | Decided |
| **Rate limiting implementation** | API Gateway, Redis | API Gateway | Open |

---

## Migration Plan (V1 → V2)

### Phase 1: Backend Development
1. Set up infrastructure
2. Implement API endpoints
3. Build data pipeline
4. Load SF data
5. Testing & validation

### Phase 2: Client Integration
1. Add RemoteZoneDataSource to iOS app
2. Implement offline fallback logic
3. Add data sync mechanism
4. Beta testing with backend

### Phase 3: Cutover
1. Parallel run (mock + API)
2. Monitor error rates
3. Disable mock data fallback
4. Remove embedded JSON from app bundle

### Rollback Plan
- Keep mock data in app for 1 version after V2 launch
- Feature flag to switch between mock and remote
- Automatic fallback to mock if API unavailable

---

**Document Owner:** Engineering Team
**Next Review:** When V2 development begins
**Related Documents:** TechnicalArchitecture.md, EngineeringProjectPlan.md
