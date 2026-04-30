// Test script for OpenDataLab API with registration number 6111203
import axios from "axios";

async function testOpenDataLab() {
  const regNumber = "6111203";
  console.log(`Testing OpenDataLab API with registration number: ${regNumber}\n`);

  try {
    // Test our backend API
    console.log("1. Testing backend API endpoint...");
    const backendResponse = await axios.get(`http://localhost:3000/api/opendatalab/search/${regNumber}`);
    console.log("Backend API Response:", JSON.stringify(backendResponse.data, null, 2));
    
    if (backendResponse.data.error) {
      console.log("\n❌ Error:", backendResponse.data.message);
    } else {
      console.log("\n✅ Success! Found organization:");
      console.log("   Name:", backendResponse.data.name);
      console.log("   Address:", backendResponse.data.address);
      console.log("   Phone:", backendResponse.data.phone);
      console.log("   Email:", backendResponse.data.email);
      console.log("   Registration:", backendResponse.data.registrationNumber);
      console.log("   Type:", backendResponse.data.type);
    }
  } catch (error) {
    console.error("\n❌ Backend API Error:", error.message);
    if (error.response) {
      console.error("   Status:", error.response.status);
      console.error("   Data:", error.response.data);
    }
  }

  try {
    // Test direct OpenDataLab API
    console.log("\n\n2. Testing direct OpenDataLab API...");
    const encodedReg = encodeURIComponent(regNumber);
    const apiUrl = `https://opendatalab.mn/api/search?q=${encodedReg}`;
    
    const directResponse = await axios.get(apiUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': 'application/json',
      },
      timeout: 10000,
    });
    
    console.log("Direct API Response:", JSON.stringify(directResponse.data, null, 2));
    
    if (directResponse.data && directResponse.data.data && directResponse.data.data.length > 0) {
      const orgData = directResponse.data.data[0];
      console.log("\n✅ Direct API Success! Found organization:");
      console.log("   Name:", orgData.name);
      console.log("   Address:", orgData.address);
      console.log("   Phone:", orgData.phone);
      console.log("   Registration:", orgData.regno);
      console.log("   Type:", orgData.type);
    } else {
      console.log("\n⚠️  No data found in direct API response");
    }
  } catch (error) {
    console.error("\n❌ Direct API Error:", error.message);
    if (error.response) {
      console.error("   Status:", error.response.status);
      console.error("   Response type:", typeof error.response.data);
      if (typeof error.response.data === 'string') {
        const preview = error.response.data.substring(0, 200);
        console.error("   Response preview:", preview);
        if (preview.includes('<!DOCTYPE') || preview.includes('<html')) {
          console.error("   ⚠️  API returned HTML instead of JSON!");
        }
      }
    }
  }
}

// Run test
testOpenDataLab().catch(console.error);



