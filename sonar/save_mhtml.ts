import { chromium } from "playwright";
import { promises as fs } from "fs";

const clickButtonIfVisible = async (page, buttonText) => {
    try {
        //const button = await page.getByRole('button', { name: buttonText });  // does not select the Dismiss button
        // const button = await page.getByRole('button', { name: buttonText, includeHidden: true });    // does not select the Dismiss button
        const button = await page.getByText(buttonText);    // not very reliable, but the only one which manages to select also the Dismiss button!
        const isButtonVisible = await button.isVisible({ timeout: 2000 });
        if (isButtonVisible) {
            console.log(`Found and clicking button with text ${buttonText}`);
            await button.click();
            await page.waitForTimeout(1000);
        } else {
            console.log(`Button found but invisible for selector ${buttonText} - continuing`);
        }
    } catch (error) {
        console.log(`No button found for selector ${buttonText} - continuing`);
    }
}

const gotoPageAndMakeMhtml = async (page, context, url, outputPath) => {
    console.log(`Go to page ${url}`);
    await page.goto(url);
    console.log(`Wait for page ${url} to be loaded`);
    await page.waitForLoadState("networkidle");
    const session = await context.newCDPSession(page);
    const { data: mhtmlData } = await session.send("Page.captureSnapshot");
    await fs.writeFile(`${outputPath}`, mhtmlData);
    console.log(`Writing the mhtml data to ${outputPath} done`);
}

(async () => {
    if (process.argv.length < 5) {
        console.error('Expected 2 arguments: --projectName and --outputFolder!');
        process.exit(1);
    }

    const projectNameIndex = process.argv.indexOf('--projectName')
    const projectName = process.argv[projectNameIndex + 1];
    if (projectNameIndex === -1 || !projectName) {
        console.error('Expected -projectName argument!');
        process.exit(1);
    }

    const outputFolderIndex = process.argv.indexOf('--outputFolder')
    const outputFolder = process.argv[outputFolderIndex + 1];
    if (outputFolderIndex === -1 || !outputFolder) {
        console.error('Expected -outputFolder argument!');
        process.exit(1);
    }

    console.log("Starting the browser...");

    const browser = await chromium.launch({ headless: true, slowMo: 0 }); // Set headless to false to show the browser window + slowMo to 5000 for example
    const context = await browser.newContext();
    const page = await context.newPage();

    const loginPageUrl = "http://localhost:9234/";
    console.log(`Go to login page ${loginPageUrl}`);
    await page.goto(loginPageUrl);
    console.log(`Wait for login page ${loginPageUrl} to be loaded`);
    await page.waitForLoadState("domcontentloaded");

    console.log("Fill in the username and password fields ...");
    await page.fill('input[name="login"]', 'admin');
    await page.fill('input[name="password"]', 'abcDEFG_S123');

    console.log("Clicking the \"Log in\" button ...");
    await page.getByRole('button', { name: 'Log in' }).click();

    await page.waitForTimeout(2000);    // Wait for navigation and potential popups

    await clickButtonIfVisible(page, 'I understand the risk');

    await page.waitForTimeout(2000);    // Wait for navigation and potential popups

    await clickButtonIfVisible(page, 'Later');

    await page.waitForTimeout(2000);    // Wait for navigation and potential popups

    await clickButtonIfVisible(page, 'Got it');

    await page.waitForTimeout(2000);    // Wait for navigation and potential popups

    await clickButtonIfVisible(page, 'Dismiss');

    await gotoPageAndMakeMhtml(page, context, `http://localhost:9234/dashboard?branch=main&id=${projectName}&codeScope=overall`, `${outputFolder}/${projectName}_overview.mhtml`);

    await gotoPageAndMakeMhtml(page, context, `http://localhost:9234/project/issues?id=${projectName}&issueStatuses=OPEN%2CCONFIRMED`, `${outputFolder}/${projectName}_issues.mhtml`);

    await gotoPageAndMakeMhtml(page, context, `http://localhost:9234/security_hotspots?id=${projectName}`, `${outputFolder}/${projectName}_security_hotspots.mhtml`);

    await browser.close();
})();
