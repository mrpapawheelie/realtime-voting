output "api_base_url" {
  description = "Invoke URL for POST /vote"
  value       = "https://${aws_api_gateway_rest_api.votes_api.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}"
}

output "votes_table_name" {
  value = aws_dynamodb_table.votes.name
}

output "intermediate_results_table_name" {
  value = aws_dynamodb_table.intermediate_results.name
}

output "kinesis_stream_name" {
  value = aws_kinesis_stream.votes_stream.name
}