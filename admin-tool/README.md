# Block Face Admin Tool

A web-based admin tool for viewing, editing, and managing block face parking data for San Francisco.

## Features

- **Interactive Map**: View all block faces on an OpenStreetMap-based interface
- **Visual Color Coding**: Block faces are color-coded by regulation type:
  - 🔴 Red: No Parking
  - ⚫ Grey: Metered Parking
  - 🟠 Orange: Time Limited
  - 🔵 Blue: Residential Permit
  - 🟣 Purple: Street Cleaning
  - 🟢 Green: Free/Other
- **Search**: Filter block faces by street name
- **Edit Interface**: Two editing modes:
  - **Fields**: User-friendly form interface for editing block face properties
  - **Raw JSON**: Direct JSON editing for advanced users
- **Regulations Management**: Add, edit, and remove parking regulations
- **Change Tracking**: All modifications are tracked in a separate customizations file
- **History View**: See all past changes made to each block face

## Prerequisites

- Node.js (v14 or higher)
- npm (Node Package Manager)

## Installation

1. Navigate to the admin-tool directory:
```bash
cd admin-tool
```

2. Install dependencies:
```bash
npm install
```

## Running the Application

1. Start the server:
```bash
npm start
```

Or for development with auto-restart:
```bash
npm run dev
```

2. Open your browser and navigate to:
```
http://localhost:3000
```

## Usage

### Loading Block Faces

1. Click the **"Load All Block Faces"** button to load all block face data
2. The map will populate with colored lines representing each block face
3. Use the search box to filter by street name

### Selecting and Editing

1. **Click on any block face** on the map to select it
2. The editor panel on the right will open with the block face data
3. Edit the data using either:
   - **Fields tab**: Edit individual fields in a form
   - **Raw JSON tab**: Edit the complete JSON object directly

### Editing Fields

- **Street**: The street name
- **From Street**: Starting cross-street
- **To Street**: Ending cross-street
- **Side**: The side of the street (EVEN, ODD, NORTH, SOUTH, EAST, WEST)

### Managing Regulations

1. Each block face can have multiple regulations
2. Click **"+ Add Regulation"** to add a new regulation
3. For each regulation, you can set:
   - Type (No Parking, Metered, Time Limit, etc.)
   - Permit Zone
   - Time Limit (in minutes)
   - Enforcement Days (comma-separated)
   - Enforcement Start/End Times
4. Click **"Remove"** on any regulation to delete it

### Saving Changes

1. After making edits, click **"Save Changes"**
2. Changes are written to the original `sample_blockfaces.json` file
3. A record of the change is saved to `customizations.json`

### Viewing History

1. Click the **"History"** tab in the editor
2. View all past customizations made to the selected block face
3. See what changed, when, and the old/new values

### Reverting Changes

- Click **"Revert"** to undo unsaved changes and restore the original data

## File Structure

```
admin-tool/
├── public/
│   ├── index.html          # Main HTML page
│   ├── styles.css          # Styling
│   └── app.js              # Frontend JavaScript
├── src/
│   └── server.js           # Express backend server
├── customizations.json     # Tracks all changes (auto-created)
├── package.json            # Node.js dependencies
└── README.md              # This file
```

## Data Files

### Input
- **Source**: `../SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces.json`
- This file is read and modified by the admin tool

### Output
- **Customizations Log**: `customizations.json`
- This file tracks all changes made through the admin tool
- Each entry includes:
  - Timestamp
  - Block face ID
  - Changed fields with old and new values
  - Complete before/after snapshots

## Integration with Pipeline

The `customizations.json` file is designed for easy integration into your data pipeline:

```json
[
  {
    "id": "custom_1234567890",
    "blockfaceId": "12345",
    "timestamp": "2025-12-01T10:30:00.000Z",
    "changes": [
      {
        "field": "street",
        "oldValue": "Main St",
        "newValue": "Main Street"
      }
    ],
    "oldData": { ... },
    "newData": { ... }
  }
]
```

You can use this file to:
- Apply customizations to fresh data imports
- Audit changes over time
- Revert specific changes if needed
- Sync customizations across environments

## API Endpoints

The backend provides the following REST API endpoints:

- `GET /api/blockfaces` - Get all block faces
- `GET /api/blockfaces/:id` - Get a specific block face
- `PUT /api/blockfaces/:id` - Update a block face
- `GET /api/customizations` - Get all customizations

## Troubleshooting

### Server won't start
- Make sure port 3000 is not in use
- Run `npm install` to ensure dependencies are installed

### Block faces don't load
- Check that the path to `sample_blockfaces.json` is correct in `src/server.js`
- Verify the JSON file exists and is valid

### Changes not saving
- Check console for errors
- Ensure the server has write permissions to the data directory
- Verify the JSON in the editor is valid before saving

## Development

To modify the admin tool:

1. **Backend** (`src/server.js`): Modify API endpoints or data handling
2. **Frontend** (`public/app.js`): Modify UI behavior and map interactions
3. **Styles** (`public/styles.css`): Modify appearance and layout
4. **HTML** (`public/index.html`): Modify page structure

## License

This tool is part of the ParkLookup project.
