package com.example.fullstackapp.model;

import org.springframework.data.annotation.Id;
import org.springframework.data.elasticsearch.annotations.DateFormat;
import org.springframework.data.elasticsearch.annotations.Document;
import org.springframework.data.elasticsearch.annotations.Field;
import org.springframework.data.elasticsearch.annotations.FieldType;
import org.springframework.data.elasticsearch.annotations.InnerField;
import org.springframework.data.elasticsearch.annotations.MultiField;
import org.springframework.data.elasticsearch.annotations.Setting;
import org.springframework.data.elasticsearch.annotations.WriteTypeHint;

import java.time.Instant;

@Document(indexName = "tasks", createIndex = false, writeTypeHint = WriteTypeHint.FALSE)
@Setting(shards = 1, replicas = 1)
public class TaskDocument {

    @Id
    private String id;

    @MultiField(
        mainField = @Field(type = FieldType.Text, analyzer = "standard"),
        otherFields = @InnerField(suffix = "keyword", type = FieldType.Keyword, ignoreAbove = 256)
    )
    private String title;

    @Field(type = FieldType.Text, analyzer = "standard")
    private String description;

    @Field(type = FieldType.Boolean)
    private boolean completed;

    @Field(type = FieldType.Date, format = {
            DateFormat.date_time,
            DateFormat.date_time_no_millis,
            DateFormat.strict_date_optional_time_nanos,
            DateFormat.epoch_millis
    })
    private Instant createdAt;

    public TaskDocument() {
    }

    public TaskDocument(String id, String title, String description, boolean completed, Instant createdAt) {
        this.id = id;
        this.title = title;
        this.description = description;
        this.completed = completed;
        this.createdAt = createdAt;
    }

    public static TaskDocument fromEntity(Task task) {
        return new TaskDocument(
                String.valueOf(task.getId()),
                task.getTitle(),
                task.getDescription() != null ? task.getDescription() : "",
                task.isCompleted(),
                task.getCreatedAt() != null ? task.getCreatedAt() : Instant.now()
        );
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getTitle() {
        return title;
    }

    public void setTitle(String title) {
        this.title = title;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public boolean isCompleted() {
        return completed;
    }

    public void setCompleted(boolean completed) {
        this.completed = completed;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }
}
