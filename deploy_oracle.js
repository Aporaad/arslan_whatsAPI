// Execute Oracle MCP tool via Node.js
// This script will call the Oracle MCP tool to deploy the WHATSAPP_BRIDGE package

const { execSync } = require('child_process');
const fs = require('fs');

const specSQL = fs.readFileSync('./wb_spec.sql', 'utf8').trim();
console.log('Deploying package spec...');
console.log(specSQL);
