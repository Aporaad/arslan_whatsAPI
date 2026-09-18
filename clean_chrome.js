const { execSync } = require('child_process');

try {
  const output = execSync('wmic process where "name=\'chrome.exe\'" get ProcessId,CommandLine /format:csv', { encoding: 'utf-8' });
  const lines = output.split('\r\n').filter(l => l.trim().length > 0);
  console.log(`Found ${lines.length} chrome process entries`);
  for (const line of lines) {
    if (line.includes('puppeteer') || line.includes('session-arslan-session') || line.includes('hp_zbook') || line.includes('.cache\\puppeteer')) {
      const parts = line.split(',');
      const pid = parts[parts.length - 1]?.trim();
      if (pid && !isNaN(pid)) {
        console.log(`Killing puppeteer chrome PID ${pid}`);
        try {
          execSync(`taskkill /F /PID ${pid}`);
        } catch (e) {
          console.error(`Failed to kill ${pid}: ${e.message}`);
        }
      }
    }
  }
} catch (e) {
  console.error('Error checking processes:', e.message);
}
