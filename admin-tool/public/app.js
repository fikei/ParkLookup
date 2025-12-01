// API Base URL
const API_BASE = 'http://localhost:3000/api';

// Global State
let allBlockfaces = [];
let selectedBlockface = null;
let originalBlockface = null;
let mapLayers = {};
let map = null;

// Initialize the application
document.addEventListener('DOMContentLoaded', () => {
    initMap();
    initEventListeners();
});

// Initialize Leaflet Map
function initMap() {
    // Center on San Francisco
    map = L.map('map').setView([37.7749, -122.4194], 13);

    // Add OpenStreetMap tiles
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© OpenStreetMap contributors',
        maxZoom: 19
    }).addTo(map);
}

// Initialize Event Listeners
function initEventListeners() {
    // Map Controls
    document.getElementById('loadAllBtn').addEventListener('click', loadAllBlockfaces);
    document.getElementById('clearMapBtn').addEventListener('click', clearMap);
    document.getElementById('searchInput').addEventListener('input', handleSearch);

    // Editor Controls
    document.getElementById('closeEditorBtn').addEventListener('click', closeEditor);
    document.getElementById('saveBtn').addEventListener('click', saveChanges);
    document.getElementById('revertBtn').addEventListener('click', revertChanges);
    document.getElementById('addRegulationBtn').addEventListener('click', addRegulation);

    // Tab Controls
    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.addEventListener('click', (e) => switchTab(e.target.dataset.tab));
    });

    // Field Updates
    ['fieldStreet', 'fieldFromStreet', 'fieldToStreet', 'fieldSide'].forEach(id => {
        document.getElementById(id).addEventListener('input', syncFieldsToJson);
    });

    document.getElementById('jsonEditor').addEventListener('input', syncJsonToFields);
}

// Load all block faces
async function loadAllBlockfaces() {
    try {
        document.getElementById('loadAllBtn').textContent = 'Loading...';
        document.getElementById('loadAllBtn').disabled = true;

        const response = await fetch(`${API_BASE}/blockfaces`);
        allBlockfaces = await response.json();

        displayBlockfacesOnMap(allBlockfaces);
        updateStats();

        document.getElementById('loadAllBtn').textContent = 'Reload Block Faces';
        document.getElementById('loadAllBtn').disabled = false;
    } catch (error) {
        console.error('Error loading blockfaces:', error);
        alert('Failed to load blockfaces. Make sure the server is running.');
        document.getElementById('loadAllBtn').textContent = 'Load All Block Faces';
        document.getElementById('loadAllBtn').disabled = false;
    }
}

// Display block faces on map
function displayBlockfacesOnMap(blockfaces) {
    // Clear existing layers
    clearMap();

    blockfaces.forEach(blockface => {
        if (!blockface.geometry || !blockface.geometry.coordinates) {
            return;
        }

        // Convert coordinates to Leaflet format (swap lon/lat)
        const latlngs = blockface.geometry.coordinates.map(coord => [coord[1], coord[0]]);

        // Determine color based on regulations
        const color = getBlockfaceColor(blockface);

        // Create polyline
        const polyline = L.polyline(latlngs, {
            color: color,
            weight: 4,
            opacity: 0.7
        }).addTo(map);

        // Add popup
        polyline.bindPopup(createPopupContent(blockface));

        // Add click handler
        polyline.on('click', () => selectBlockface(blockface));

        // Store layer
        mapLayers[blockface.id] = polyline;
    });

    // Fit map to show all blockfaces
    if (blockfaces.length > 0 && Object.keys(mapLayers).length > 0) {
        const group = L.featureGroup(Object.values(mapLayers));
        map.fitBounds(group.getBounds());
    }
}

// Get blockface color based on regulations
function getBlockfaceColor(blockface) {
    if (!blockface.regulations || blockface.regulations.length === 0) {
        return '#999999'; // Grey for no regulations
    }

    // Priority: No Parking > Metered > Time Limit > Permit > Free
    const types = blockface.regulations.map(r => r.type);

    if (types.includes('noParking')) return '#e74c3c'; // Red
    if (types.includes('metered')) return '#95a5a6'; // Grey
    if (types.includes('timeLimit')) return '#e67e22'; // Orange
    if (types.includes('residentialPermit')) return '#3498db'; // Blue
    if (types.includes('streetCleaning')) return '#9b59b6'; // Purple

    return '#27ae60'; // Green for free/other
}

// Create popup content
function createPopupContent(blockface) {
    let content = `<div class="popup-content">`;
    content += `<div class="popup-title">${blockface.street || 'Unknown Street'}</div>`;
    content += `<div class="popup-info">`;
    content += `<strong>ID:</strong> ${blockface.id}<br>`;
    if (blockface.fromStreet) content += `<strong>From:</strong> ${blockface.fromStreet}<br>`;
    if (blockface.toStreet) content += `<strong>To:</strong> ${blockface.toStreet}<br>`;
    content += `<strong>Side:</strong> ${blockface.side || 'N/A'}<br>`;
    content += `<strong>Regulations:</strong> ${blockface.regulations?.length || 0}`;
    content += `</div>`;
    content += `<button onclick="selectBlockfaceById('${blockface.id}')" style="margin-top: 0.5rem; padding: 0.25rem 0.5rem; background: #3498db; color: white; border: none; border-radius: 3px; cursor: pointer;">Edit</button>`;
    content += `</div>`;
    return content;
}

// Select blockface by ID (for popup button)
window.selectBlockfaceById = function(id) {
    const blockface = allBlockfaces.find(bf => bf.id === id);
    if (blockface) {
        selectBlockface(blockface);
    }
};

// Select a blockface for editing
function selectBlockface(blockface) {
    selectedBlockface = JSON.parse(JSON.stringify(blockface)); // Deep clone
    originalBlockface = JSON.parse(JSON.stringify(blockface)); // Deep clone

    // Highlight selected blockface
    Object.values(mapLayers).forEach(layer => {
        layer.setStyle({ weight: 4, opacity: 0.7 });
    });

    if (mapLayers[blockface.id]) {
        mapLayers[blockface.id].setStyle({ weight: 6, opacity: 1 });
    }

    // Show editor
    document.getElementById('noSelection').classList.add('hidden');
    document.getElementById('editorContent').classList.remove('hidden');

    // Populate editor
    populateEditor(selectedBlockface);
    loadHistory(blockface.id);

    updateStats();
}

// Populate editor with blockface data
function populateEditor(blockface) {
    document.getElementById('editorTitle').textContent = blockface.street || 'Block Face Editor';
    document.getElementById('fieldId').value = blockface.id || '';
    document.getElementById('fieldStreet').value = blockface.street || '';
    document.getElementById('fieldFromStreet').value = blockface.fromStreet || '';
    document.getElementById('fieldToStreet').value = blockface.toStreet || '';
    document.getElementById('fieldSide').value = blockface.side || 'EVEN';

    // Populate regulations
    populateRegulations(blockface.regulations || []);

    // Populate JSON editor
    document.getElementById('jsonEditor').value = JSON.stringify(blockface, null, 2);
}

// Populate regulations list
function populateRegulations(regulations) {
    const container = document.getElementById('regulationsContainer');
    container.innerHTML = '';

    regulations.forEach((regulation, index) => {
        const regDiv = document.createElement('div');
        regDiv.className = 'regulation-item';
        regDiv.dataset.index = index;

        regDiv.innerHTML = `
            <div class="regulation-header">
                <h4>Regulation ${index + 1}</h4>
                <button class="regulation-remove" onclick="removeRegulation(${index})">Remove</button>
            </div>
            <div class="form-group">
                <label>Type</label>
                <select class="reg-type" data-index="${index}">
                    <option value="noParking" ${regulation.type === 'noParking' ? 'selected' : ''}>No Parking</option>
                    <option value="metered" ${regulation.type === 'metered' ? 'selected' : ''}>Metered</option>
                    <option value="timeLimit" ${regulation.type === 'timeLimit' ? 'selected' : ''}>Time Limit</option>
                    <option value="residentialPermit" ${regulation.type === 'residentialPermit' ? 'selected' : ''}>Residential Permit</option>
                    <option value="streetCleaning" ${regulation.type === 'streetCleaning' ? 'selected' : ''}>Street Cleaning</option>
                    <option value="other" ${regulation.type === 'other' ? 'selected' : ''}>Other</option>
                </select>
            </div>
            <div class="form-group">
                <label>Permit Zone</label>
                <input type="text" class="reg-permitZone" data-index="${index}" value="${regulation.permitZone || ''}" />
            </div>
            <div class="form-group">
                <label>Time Limit (minutes)</label>
                <input type="number" class="reg-timeLimit" data-index="${index}" value="${regulation.timeLimit || ''}" />
            </div>
            <div class="form-group">
                <label>Enforcement Days (comma-separated)</label>
                <input type="text" class="reg-enforcementDays" data-index="${index}" value="${regulation.enforcementDays?.join(', ') || ''}" />
            </div>
            <div class="form-group">
                <label>Enforcement Start</label>
                <input type="text" class="reg-enforcementStart" data-index="${index}" value="${regulation.enforcementStart || ''}" placeholder="HH:MM" />
            </div>
            <div class="form-group">
                <label>Enforcement End</label>
                <input type="text" class="reg-enforcementEnd" data-index="${index}" value="${regulation.enforcementEnd || ''}" placeholder="HH:MM" />
            </div>
        `;

        container.appendChild(regDiv);

        // Add change listeners
        regDiv.querySelectorAll('input, select').forEach(input => {
            input.addEventListener('input', syncFieldsToJson);
        });
    });
}

// Add new regulation
window.addRegulation = function() {
    if (!selectedBlockface) return;

    if (!selectedBlockface.regulations) {
        selectedBlockface.regulations = [];
    }

    selectedBlockface.regulations.push({
        type: 'timeLimit',
        timeLimit: 120,
        enforcementDays: ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'],
        enforcementStart: '08:00',
        enforcementEnd: '18:00'
    });

    populateRegulations(selectedBlockface.regulations);
    syncFieldsToJson();
};

// Remove regulation
window.removeRegulation = function(index) {
    if (!selectedBlockface || !selectedBlockface.regulations) return;

    selectedBlockface.regulations.splice(index, 1);
    populateRegulations(selectedBlockface.regulations);
    syncFieldsToJson();
};

// Sync fields to JSON
function syncFieldsToJson() {
    if (!selectedBlockface) return;

    // Update basic fields
    selectedBlockface.street = document.getElementById('fieldStreet').value;
    selectedBlockface.fromStreet = document.getElementById('fieldFromStreet').value;
    selectedBlockface.toStreet = document.getElementById('fieldToStreet').value;
    selectedBlockface.side = document.getElementById('fieldSide').value;

    // Update regulations
    const regElements = document.querySelectorAll('.regulation-item');
    selectedBlockface.regulations = Array.from(regElements).map(regDiv => {
        const index = regDiv.dataset.index;
        const type = regDiv.querySelector('.reg-type').value;
        const permitZone = regDiv.querySelector('.reg-permitZone').value;
        const timeLimit = regDiv.querySelector('.reg-timeLimit').value;
        const enforcementDays = regDiv.querySelector('.reg-enforcementDays').value
            .split(',')
            .map(d => d.trim())
            .filter(d => d);
        const enforcementStart = regDiv.querySelector('.reg-enforcementStart').value;
        const enforcementEnd = regDiv.querySelector('.reg-enforcementEnd').value;

        const regulation = { type };
        if (permitZone) regulation.permitZone = permitZone;
        if (timeLimit) regulation.timeLimit = parseInt(timeLimit);
        if (enforcementDays.length > 0) regulation.enforcementDays = enforcementDays;
        if (enforcementStart) regulation.enforcementStart = enforcementStart;
        if (enforcementEnd) regulation.enforcementEnd = enforcementEnd;

        return regulation;
    });

    // Update JSON editor
    document.getElementById('jsonEditor').value = JSON.stringify(selectedBlockface, null, 2);
}

// Sync JSON to fields
function syncJsonToFields() {
    try {
        const json = document.getElementById('jsonEditor').value;
        selectedBlockface = JSON.parse(json);
        populateEditor(selectedBlockface);
    } catch (error) {
        // Invalid JSON, don't update
        console.error('Invalid JSON:', error);
    }
}

// Switch tabs
function switchTab(tabName) {
    // Update buttons
    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.tab === tabName);
    });

    // Update content
    document.querySelectorAll('.tab-content').forEach(content => {
        content.classList.toggle('active', content.id === `${tabName}Tab`);
    });
}

// Save changes
async function saveChanges() {
    if (!selectedBlockface) return;

    try {
        const response = await fetch(`${API_BASE}/blockfaces/${selectedBlockface.id}`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(selectedBlockface)
        });

        const result = await response.json();

        if (result.success) {
            // Update local data
            const index = allBlockfaces.findIndex(bf => bf.id === selectedBlockface.id);
            if (index !== -1) {
                allBlockfaces[index] = selectedBlockface;
            }

            // Update map
            if (mapLayers[selectedBlockface.id]) {
                map.removeLayer(mapLayers[selectedBlockface.id]);
                delete mapLayers[selectedBlockface.id];
            }
            displayBlockfacesOnMap([selectedBlockface]);

            // Update original
            originalBlockface = JSON.parse(JSON.stringify(selectedBlockface));

            alert('Changes saved successfully!');
            loadHistory(selectedBlockface.id);
        } else {
            alert('Failed to save changes: ' + result.error);
        }
    } catch (error) {
        console.error('Error saving changes:', error);
        alert('Failed to save changes. Please try again.');
    }
}

// Revert changes
function revertChanges() {
    if (!originalBlockface) return;

    selectedBlockface = JSON.parse(JSON.stringify(originalBlockface));
    populateEditor(selectedBlockface);
}

// Close editor
function closeEditor() {
    selectedBlockface = null;
    originalBlockface = null;

    document.getElementById('editorContent').classList.add('hidden');
    document.getElementById('noSelection').classList.remove('hidden');

    // Reset map highlighting
    Object.values(mapLayers).forEach(layer => {
        layer.setStyle({ weight: 4, opacity: 0.7 });
    });

    updateStats();
}

// Load history for a blockface
async function loadHistory(blockfaceId) {
    try {
        const response = await fetch(`${API_BASE}/customizations`);
        const customizations = await response.json();

        const blockfaceCustomizations = customizations.filter(c => c.blockfaceId === blockfaceId);

        const container = document.getElementById('historyContainer');

        if (blockfaceCustomizations.length === 0) {
            container.innerHTML = '<p>No customizations yet for this block face.</p>';
            return;
        }

        container.innerHTML = blockfaceCustomizations.map(custom => {
            const date = new Date(custom.timestamp).toLocaleString();
            const changesHtml = custom.changes.map(change => {
                return `
                    <div class="change">
                        <strong>${change.field}:</strong>
                        <span class="old-value">${JSON.stringify(change.oldValue)}</span>
                        →
                        <span class="new-value">${JSON.stringify(change.newValue)}</span>
                    </div>
                `;
            }).join('');

            return `
                <div class="history-item">
                    <h4>Customization</h4>
                    <div class="timestamp">${date}</div>
                    ${changesHtml}
                </div>
            `;
        }).join('');
    } catch (error) {
        console.error('Error loading history:', error);
    }
}

// Handle search
function handleSearch(e) {
    const searchTerm = e.target.value.toLowerCase();

    if (!searchTerm) {
        displayBlockfacesOnMap(allBlockfaces);
        return;
    }

    const filtered = allBlockfaces.filter(bf => {
        return (bf.street && bf.street.toLowerCase().includes(searchTerm)) ||
               (bf.fromStreet && bf.fromStreet.toLowerCase().includes(searchTerm)) ||
               (bf.toStreet && bf.toStreet.toLowerCase().includes(searchTerm));
    });

    displayBlockfacesOnMap(filtered);
}

// Clear map
function clearMap() {
    Object.values(mapLayers).forEach(layer => map.removeLayer(layer));
    mapLayers = {};
    updateStats();
}

// Update stats
function updateStats() {
    document.getElementById('totalCount').textContent = `Total: ${Object.keys(mapLayers).length}`;
    document.getElementById('selectedCount').textContent = selectedBlockface
        ? `Selected: ${selectedBlockface.street || selectedBlockface.id}`
        : 'Selected: None';
}
