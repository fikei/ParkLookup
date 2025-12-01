const express = require('express');
const cors = require('cors');
const fs = require('fs').promises;
const path = require('path');

const app = express();
const PORT = 3000;

// Paths to data files
const BLOCKFACES_PATH = path.join(__dirname, '../../SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces.json');
const CUSTOMIZATIONS_PATH = path.join(__dirname, '../customizations.json');

// Middleware
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.static(path.join(__dirname, '../public')));

// Get all block faces
app.get('/api/blockfaces', async (req, res) => {
    try {
        const data = await fs.readFile(BLOCKFACES_PATH, 'utf-8');
        const blockfaces = JSON.parse(data);
        res.json(blockfaces);
    } catch (error) {
        console.error('Error reading blockfaces:', error);
        res.status(500).json({ error: 'Failed to load blockfaces' });
    }
});

// Get a single block face by ID
app.get('/api/blockfaces/:id', async (req, res) => {
    try {
        const data = await fs.readFile(BLOCKFACES_PATH, 'utf-8');
        const blockfaces = JSON.parse(data);
        const blockface = blockfaces.find(bf => bf.id === req.params.id);

        if (!blockface) {
            return res.status(404).json({ error: 'Block face not found' });
        }

        res.json(blockface);
    } catch (error) {
        console.error('Error reading blockface:', error);
        res.status(500).json({ error: 'Failed to load blockface' });
    }
});

// Update a block face
app.put('/api/blockfaces/:id', async (req, res) => {
    try {
        // Read current blockfaces
        const data = await fs.readFile(BLOCKFACES_PATH, 'utf-8');
        const blockfaces = JSON.parse(data);

        // Find and update the blockface
        const index = blockfaces.findIndex(bf => bf.id === req.params.id);
        if (index === -1) {
            return res.status(404).json({ error: 'Block face not found' });
        }

        const oldBlockface = blockfaces[index];
        const newBlockface = req.body;

        // Update the blockface
        blockfaces[index] = newBlockface;

        // Save updated blockfaces
        await fs.writeFile(BLOCKFACES_PATH, JSON.stringify(blockfaces, null, 2));

        // Track customization
        await trackCustomization(req.params.id, oldBlockface, newBlockface);

        res.json({ success: true, blockface: newBlockface });
    } catch (error) {
        console.error('Error updating blockface:', error);
        res.status(500).json({ error: 'Failed to update blockface' });
    }
});

// Get all customizations
app.get('/api/customizations', async (req, res) => {
    try {
        const exists = await fs.access(CUSTOMIZATIONS_PATH).then(() => true).catch(() => false);
        if (!exists) {
            return res.json([]);
        }

        const data = await fs.readFile(CUSTOMIZATIONS_PATH, 'utf-8');
        const customizations = JSON.parse(data);
        res.json(customizations);
    } catch (error) {
        console.error('Error reading customizations:', error);
        res.status(500).json({ error: 'Failed to load customizations' });
    }
});

// Track a customization
async function trackCustomization(blockfaceId, oldData, newData) {
    try {
        let customizations = [];

        // Read existing customizations
        const exists = await fs.access(CUSTOMIZATIONS_PATH).then(() => true).catch(() => false);
        if (exists) {
            const data = await fs.readFile(CUSTOMIZATIONS_PATH, 'utf-8');
            customizations = JSON.parse(data);
        }

        // Add new customization
        const customization = {
            id: `custom_${Date.now()}`,
            blockfaceId,
            timestamp: new Date().toISOString(),
            changes: getChanges(oldData, newData),
            oldData,
            newData
        };

        customizations.push(customization);

        // Save customizations
        await fs.writeFile(CUSTOMIZATIONS_PATH, JSON.stringify(customizations, null, 2));
    } catch (error) {
        console.error('Error tracking customization:', error);
    }
}

// Helper function to get changes between objects
function getChanges(oldObj, newObj, prefix = '') {
    const changes = [];

    const allKeys = new Set([...Object.keys(oldObj), ...Object.keys(newObj)]);

    for (const key of allKeys) {
        const fullKey = prefix ? `${prefix}.${key}` : key;
        const oldVal = oldObj[key];
        const newVal = newObj[key];

        if (JSON.stringify(oldVal) !== JSON.stringify(newVal)) {
            if (typeof oldVal === 'object' && typeof newVal === 'object' && oldVal !== null && newVal !== null && !Array.isArray(oldVal)) {
                changes.push(...getChanges(oldVal, newVal, fullKey));
            } else {
                changes.push({
                    field: fullKey,
                    oldValue: oldVal,
                    newValue: newVal
                });
            }
        }
    }

    return changes;
}

app.listen(PORT, () => {
    console.log(`Block face admin tool running at http://localhost:${PORT}`);
});
