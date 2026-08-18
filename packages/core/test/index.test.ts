import { describe, expect, it } from "vitest";

import { helperProtocolVersion } from "../src/index";

describe("helper protocol", () =>
{
    it("starts at version one", () =>
    {
        expect(helperProtocolVersion).toBe(1);
    });
});
