// Initialize charts
let temperatureChart, humidityChart;
let currentDeviceId = null;

// Set up charts when page loads
document.addEventListener('DOMContentLoaded', function() {
    // Initialize empty charts
    setupCharts();
    
    // Add click event to device cards
    const deviceCards = document.querySelectorAll('.device-card');
    deviceCards.forEach(card => {
        card.addEventListener('click', function() {
            const deviceId = this.getAttribute('data-device-id');
            loadDeviceData(deviceId);
            
            // Highlight selected device
            deviceCards.forEach(c => c.classList.remove('selected'));
            this.classList.add('selected');
            
            currentDeviceId = deviceId;
        });
    });
    
    // Load first device data if available
    if (deviceCards.length > 0) {
        const firstDeviceId = deviceCards[0].getAttribute('data-device-id');
        loadDeviceData(firstDeviceId);
        deviceCards[0].classList.add('selected');
        currentDeviceId = firstDeviceId;
    }
});

// Load device data using AJAX
function loadDeviceData(deviceId) {
    fetch(`/api/readings/?device_id=${deviceId}`)
        .then(response => response.json())
        .then(data => {
            // Process data for charts
            const temperatureData = [];
            const humidityData = [];
            
            data.forEach(reading => {
                const timestamp = new Date(reading.timestamp);
                
                if (reading.temperature !== null) {
                    temperatureData.push({
                        x: timestamp,
                        y: reading.temperature
                    });
                }
                
                if (reading.humidity !== null) {
                    humidityData.push({
                        x: timestamp,
                        y: reading.humidity
                    });
                }
            });
            
            // Update charts
            updateCharts(temperatureData, humidityData);
            
            // Display latest data
            if (data.length > 0) {
                updateCurrentReadings(data[0]);
            }
        })
        .catch(error => console.error('Error loading device data:', error));
}

// Set up empty charts
function setupCharts() {
    const tempCtx = document.getElementById('temperature-chart').getContext('2d');
    const humCtx = document.getElementById('humidity-chart').getContext('2d');
    
    temperatureChart = new Chart(tempCtx, {
        type: 'line',
        data: {
            datasets: [{
                label: 'Temperature (°C)',
                borderColor: 'rgb(255, 99, 132)',
                backgroundColor: 'rgba(255, 99, 132, 0.1)',
                borderWidth: 2,
                data: []
            }]
        },
        options: {
            scales: {
                x: {
                    type: 'time',
                    time: {
                        unit: 'hour'
                    }
                },
                y: {
                    beginAtZero: false
                }
            }
        }
    });
    
    humidityChart = new Chart(humCtx, {
        type: 'line',
        data: {
            datasets: [{
                label: 'Humidity (%)',
                borderColor: 'rgb(54, 162, 235)',
                backgroundColor: 'rgba(54, 162, 235, 0.1)',
                borderWidth: 2,
                data: []
            }]
        },
        options: {
            scales: {
                x: {
                    type: 'time',
                    time: {
                        unit: 'hour'
                    }
                },
                y: {
                    beginAtZero: true,
                    max: 100
                }
            }
        }
    });
}

// Update charts with new data
function updateCharts(temperatureData, humidityData) {
    temperatureChart.data.datasets[0].data = temperatureData;
    temperatureChart.update();
    
    humidityChart.data.datasets[0].data = humidityData;
    humidityChart.update();
}

// Update current readings display
function updateCurrentReadings(data) {
    let html = '';
    
    if (data.temperature !== null) {
        html += `<p>Temperature: ${data.temperature}°C</p>`;
    }
    
    if (data.humidity !== null) {
        html += `<p>Humidity: ${data.humidity}%</p>`;
    }
    
    if (data.pressure !== null) {
        html += `<p>Pressure: ${data.pressure} hPa</p>`;
    }
    
    if (data.voltage !== null) {
        html += `<p>Voltage: ${data.voltage} V</p>`;
    }
    
    html += `<p>Timestamp: ${new Date(data.timestamp).toLocaleString()}</p>`;
    
    document.getElementById('current-readings').innerHTML = html;
}

// Add data point to chart (for real-time updates)
function addDataPoint(chart, timestamp, value) {
    if (value !== null && value !== undefined) {
        chart.data.datasets[0].data.push({
            x: new Date(timestamp),
            y: value
        });
        
        // Keep only last 100 points for performance
        if (chart.data.datasets[0].data.length > 100) {
            chart.data.datasets[0].data.shift();
        }
        
        chart.update();
    }
}
