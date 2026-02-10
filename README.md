# DefectDojo GitHub Action

A GitHub Action to import security scan results into [DefectDojo](https://github.com/DefectDojo/django-DefectDojo).

This action allows you to:

- Import scan reports (e.g., Trivy, ZAP, Gitleaks, etc.)
- Automatically create or resolve **Products** by name.
- Automatically create **Engagements** for each run.

## Usage

### Basic Example

```yaml
steps:
  - name: Checkout code
    uses: actions/checkout@v6

  - name: Run Trivy Scan
    run: trivy fs . --format json -o trivy-results.json

  - name: Import to DefectDojo
    uses: ./ # Or olamilekan000/defectdojo-action@v1
    with:
      defectdojo_url: ${{ secrets.DEFECTDOJO_URL }}
      api_key: ${{ secrets.DEFECTDOJO_API_KEY }}
      file: trivy-results.json
      scan_type: "Trivy Scan"
      product_name: "My Application"
      engagement_name: "CI Scan - ${{ github.run_id }}"
```

### Advanced Example

Reuse existing Product and Engagement IDs:

```yaml
- name: Import to DefectDojo
  uses: ./
  with:
    defectdojo_url: ${{ secrets.DEFECTDOJO_URL }}
    api_key: ${{ secrets.DEFECTDOJO_API_KEY }}
    file: zap.xml
    scan_type: "ZAP Scan"
    product_id: 42
    engagement_id: 101
    minimum_severity: "High"
    active: "true"
    verified: "false"
```

## Inputs

| Input                | Description                              | Required | Default |
| -------------------- | ---------------------------------------- | -------- | ------- |
| `defectdojo_url`     | Base URL of your DefectDojo instance     | **Yes**  |         |
| `api_key`            | DefectDojo API v2 Key                    | **Yes**  |         |
| `file`               | Path to the scan report file             | **Yes**  |         |
| `scan_type`          | DefectDojo Scan Type (e.g. `Trivy Scan`) | **Yes**  |         |
| `product_name`       | Name of the product to find or create    | No       |         |
| `product_id`         | ID of an existing product                | No       |         |
| `engagement_name`    | Name of the engagement to create         | No       |         |
| `engagement_id`      | ID of an existing engagement             | No       |         |
| `product_type`       | Product Type ID for new products         | No       | `1`     |
| `minimum_severity`   | Min severity (Info, Low, Medium, High)   | No       | `Info`  |
| `active`             | Mark findings as active                  | No       | `true`  |
| `verified`           | Mark findings as verified                | No       | `true`  |
| `close_old_findings` | Close old findings (for reimport)        | No       | `false` |

**Note**: You must provide either (`product_id`) OR (`product_name`). Similarly for engagements.

## Outputs

| Output          | Description                                 |
| --------------- | ------------------------------------------- |
| `product_id`    | The ID of the product used or created.      |
| `engagement_id` | The ID of the engagement used or created.   |
| `test_id`       | The ID of the scan test created.            |
| `response`      | The full JSON response from the import API. |
